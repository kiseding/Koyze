// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

#include "desktop_media.h"

#include <cstdio>
#include <cstring>

namespace {

constexpr char kBusName[] = "org.mpris.MediaPlayer2.koyze";
constexpr char kObjectPath[] = "/org/mpris/MediaPlayer2";
constexpr char kRootInterface[] = "org.mpris.MediaPlayer2";
constexpr char kPlayerInterface[] = "org.mpris.MediaPlayer2.Player";
constexpr char kNoTrackPath[] = "/org/mpris/MediaPlayer2/TrackList/NoTrack";

// 只声明真正会响应的成员：CanQuit / HasTrackList 之类要按能力如实回答，
// 声明了却不实现会让播放器被系统面板标成"假货"，按钮点了没反应。
constexpr char kIntrospectionXml[] = R"XML(
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek">
      <arg name="Offset" type="x" direction="in"/>
    </method>
    <method name="SetPosition">
      <arg name="TrackId" type="o" direction="in"/>
      <arg name="Position" type="x" direction="in"/>
    </method>
    <method name="OpenUri">
      <arg name="Uri" type="s" direction="in"/>
    </method>
    <signal name="Seeked">
      <arg name="Position" type="x"/>
    </signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
)XML";

std::string StringField(FlValue* map, const char* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return std::string();
  }
  const gchar* text = fl_value_get_string(value);
  return text == nullptr ? std::string() : std::string(text);
}

int64_t IntField(FlValue* map, const char* key, int64_t fallback) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr) return fallback;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return fl_value_get_int(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<int64_t>(fl_value_get_float(value));
  }
  return fallback;
}

bool BoolField(FlValue* map, const char* key, bool fallback) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

GDBusInterfaceVTable VTable() {
  GDBusInterfaceVTable vtable = {};
  vtable.method_call = DesktopMedia::OnPlayerMethodCall;
  vtable.get_property = DesktopMedia::OnGetProperty;
  vtable.set_property = DesktopMedia::OnSetProperty;
  return vtable;
}

}  // namespace

DesktopMedia::DesktopMedia(FlMethodChannel* channel) : channel_(channel) {
  if (channel_ != nullptr) {
    g_object_ref(channel_);
  }
}

DesktopMedia::~DesktopMedia() {
  if (owner_id_ != 0) {
    g_bus_unown_name(owner_id_);
    owner_id_ = 0;
  }
  if (connection_ != nullptr) {
    if (root_registration_ != 0) {
      g_dbus_connection_unregister_object(connection_, root_registration_);
      root_registration_ = 0;
    }
    if (player_registration_ != 0) {
      g_dbus_connection_unregister_object(connection_, player_registration_);
      player_registration_ = 0;
    }
    g_object_unref(connection_);
    connection_ = nullptr;
  }
  if (node_info_ != nullptr) {
    g_dbus_node_info_unref(node_info_);
    node_info_ = nullptr;
  }
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }
}

void DesktopMedia::HandleMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(GError) error = nullptr;

  if (g_strcmp0(method, "initialize") == 0) {
    EnsureRegistered();
    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }
  if (g_strcmp0(method, "update") == 0) {
    UpdateFromMap(args);
    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }
  if (g_strcmp0(method, "clear") == 0) {
    ClearTrack();
    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }
  fl_method_call_respond_not_implemented(method_call, &error);
}

void DesktopMedia::EnsureRegistered() {
  if (registered_) return;
  g_autoptr(GError) error = nullptr;
  connection_ = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (connection_ == nullptr) {
    // 无桌面会话（CI、SSH、纯 Wayland 无 dbus-launch）时静默降级：
    // 播放本身不依赖 MPRIS。
    g_printerr("[koyze] MPRIS unavailable: %s\n",
               error != nullptr ? error->message : "no session bus");
    return;
  }

  node_info_ = g_dbus_node_info_new_for_xml(kIntrospectionXml, &error);
  if (node_info_ == nullptr) {
    g_printerr("[koyze] MPRIS introspection failed: %s\n",
               error != nullptr ? error->message : "invalid xml");
    return;
  }

  const GDBusInterfaceVTable vtable = VTable();
  // GDBusNodeInfo 没有 n_interfaces 字段：interfaces 是一个以 NULL 结尾的
  // 数组，只能按哨兵遍历。
  for (gint i = 0;
       node_info_->interfaces != nullptr && node_info_->interfaces[i] != nullptr;
       i++) {
    GDBusInterfaceInfo* info = node_info_->interfaces[i];
    const guint registration = g_dbus_connection_register_object(
        connection_, kObjectPath, info, &vtable, this, nullptr, &error);
    if (registration == 0) {
      g_printerr("[koyze] MPRIS register %s failed: %s\n", info->name,
                 error != nullptr ? error->message : "unknown error");
      continue;
    }
    if (g_strcmp0(info->name, kRootInterface) == 0) {
      root_registration_ = registration;
    } else if (g_strcmp0(info->name, kPlayerInterface) == 0) {
      player_registration_ = registration;
    }
  }

  if (root_registration_ == 0 && player_registration_ == 0) return;

  owner_id_ = g_bus_own_name_on_connection(
      connection_, kBusName, G_BUS_NAME_OWNER_FLAGS_NONE, OnNameAcquired,
      OnNameLost, this, nullptr);
  registered_ = true;
  track_path_ = kNoTrackPath;
}

void DesktopMedia::UpdateFromMap(FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return;
  }
  const std::string identity = StringField(args, "identity");
  const std::string artwork = StringField(args, "artworkPath");
  const bool track_changed = !track_.has_track || identity != track_.identity;

  track_.has_track = true;
  track_.identity = identity;
  track_.title = StringField(args, "title");
  track_.artist = StringField(args, "artist");
  track_.album = StringField(args, "album");
  track_.artwork_path = artwork;
  track_.duration_ms = IntField(args, "durationMs", 0);
  track_.position_ms = IntField(args, "positionMs", 0);
  track_.playing = BoolField(args, "playing", false);
  track_.can_next = BoolField(args, "canGoNext", true);
  track_.can_previous = BoolField(args, "canGoPrevious", true);
  track_.sampled_us = g_get_monotonic_time();

  if (identity.empty()) {
    track_path_ = kNoTrackPath;
  } else {
    g_autofree gchar* path = g_strdup_printf(
        "/com/koyze/track/%u", g_str_hash(identity.c_str()));
    track_path_ = path;
  }

  if (!registered_) return;
  NotifyPropertiesChanged(track_changed || !artwork.empty());
}

void DesktopMedia::ClearTrack() {
  track_ = Track();
  track_path_ = kNoTrackPath;
  if (!registered_) return;
  NotifyPropertiesChanged(true);
}

const char* DesktopMedia::PlaybackStatus() const {
  if (!track_.has_track) return "Stopped";
  return track_.playing ? "Playing" : "Paused";
}

int64_t DesktopMedia::CurrentPositionMs() const {
  if (!track_.has_track) return 0;
  if (!track_.playing) return track_.position_ms;
  const int64_t elapsed_ms = (g_get_monotonic_time() - track_.sampled_us) / 1000;
  int64_t position = track_.position_ms + elapsed_ms;
  if (position < 0) position = 0;
  if (track_.duration_ms > 0 && position > track_.duration_ms) {
    position = track_.duration_ms;
  }
  return position;
}

const char* DesktopMedia::TrackObjectPath() const {
  return track_path_.empty() ? kNoTrackPath : track_path_.c_str();
}

GVariant* DesktopMedia::BuildMetadata() const {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  if (!track_.has_track) {
    return g_variant_builder_end(&builder);
  }
  g_variant_builder_add(&builder, "{sv}", "mpris:trackid",
                        g_variant_new_object_path(TrackObjectPath()));
  g_variant_builder_add(&builder, "{sv}", "mpris:length",
                        g_variant_new_int64(track_.duration_ms * 1000));
  if (!track_.artwork_path.empty()) {
    g_autofree gchar* uri =
        g_filename_to_uri(track_.artwork_path.c_str(), nullptr, nullptr);
    if (uri != nullptr) {
      g_variant_builder_add(&builder, "{sv}", "mpris:artUrl",
                            g_variant_new_string(uri));
    }
  }
  g_variant_builder_add(&builder, "{sv}", "xesam:title",
                        g_variant_new_string(track_.title.c_str()));
  const gchar* artists[] = {track_.artist.c_str(), nullptr};
  g_variant_builder_add(&builder, "{sv}", "xesam:artist",
                        g_variant_new_strv(artists, -1));
  g_variant_builder_add(&builder, "{sv}", "xesam:album",
                        g_variant_new_string(track_.album.c_str()));
  return g_variant_builder_end(&builder);
}

void DesktopMedia::NotifyPropertiesChanged(bool include_metadata) {
  if (connection_ == nullptr) return;
  GVariantBuilder changed;
  g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&changed, "{sv}", "PlaybackStatus",
                        g_variant_new_string(PlaybackStatus()));
  if (include_metadata) {
    g_variant_builder_add(&changed, "{sv}", "Metadata", BuildMetadata());
  }
  g_variant_builder_add(&changed, "{sv}", "CanGoNext",
                        g_variant_new_boolean(track_.can_next));
  g_variant_builder_add(&changed, "{sv}", "CanGoPrevious",
                        g_variant_new_boolean(track_.can_previous));
  g_variant_builder_add(&changed, "{sv}", "CanPlay",
                        g_variant_new_boolean(track_.has_track));
  g_variant_builder_add(&changed, "{sv}", "CanPause",
                        g_variant_new_boolean(track_.has_track));
  g_variant_builder_add(&changed, "{sv}", "CanSeek",
                        g_variant_new_boolean(track_.has_track));
  g_variant_builder_add(&changed, "{sv}", "CanControl",
                        g_variant_new_boolean(true));

  GVariantBuilder invalidated;
  g_variant_builder_init(&invalidated, G_VARIANT_TYPE("as"));
  g_autoptr(GError) error = nullptr;
  g_dbus_connection_emit_signal(
      connection_, nullptr, kObjectPath, "org.freedesktop.DBus.Properties",
      "PropertiesChanged",
      g_variant_new("(sa{sv}as)", kPlayerInterface, &changed, &invalidated),
      &error);
  if (error != nullptr) {
    g_printerr("[koyze] MPRIS PropertiesChanged failed: %s\n", error->message);
  }
}

void DesktopMedia::EmitSeeked(int64_t position_ms) {
  if (connection_ == nullptr) return;
  g_autoptr(GError) error = nullptr;
  g_dbus_connection_emit_signal(connection_, nullptr, kObjectPath,
                                kPlayerInterface, "Seeked",
                                g_variant_new("(x)", position_ms * 1000),
                                &error);
}

void DesktopMedia::SendCommand(const char* command) {
  if (channel_ == nullptr) return;
  fl_method_channel_invoke_method(channel_, command, nullptr, nullptr, nullptr,
                                  nullptr);
}

void DesktopMedia::SendIntCommand(const char* command, int64_t value) {
  if (channel_ == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_int(value);
  fl_method_channel_invoke_method(channel_, command, args, nullptr, nullptr,
                                  nullptr);
}

void DesktopMedia::OnMethodCall(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  auto* self = static_cast<DesktopMedia*>(user_data);
  if (self == nullptr) return;
  self->HandleMethodCall(method_call);
}

void DesktopMedia::OnPlayerMethodCall(GDBusConnection* connection,
                                      const gchar* sender,
                                      const gchar* object_path,
                                      const gchar* interface_name,
                                      const gchar* method_name,
                                      GVariant* parameters,
                                      GDBusMethodInvocation* invocation,
                                      gpointer user_data) {
  auto* self = static_cast<DesktopMedia*>(user_data);
  if (self == nullptr) {
    return;
  }

  if (g_strcmp0(interface_name, kRootInterface) == 0) {
    if (g_strcmp0(method_name, "Raise") == 0) {
      g_dbus_method_invocation_return_value(invocation, nullptr);
      return;
    }
    g_dbus_method_invocation_return_dbus_error(
        invocation, "org.freedesktop.DBus.Error.NotSupported",
        "Koyze 不通过 MPRIS 退出，请使用窗口菜单。");
    return;
  }

  if (g_strcmp0(method_name, "Next") == 0) {
    self->SendCommand("next");
  } else if (g_strcmp0(method_name, "Previous") == 0) {
    self->SendCommand("previous");
  } else if (g_strcmp0(method_name, "Pause") == 0) {
    self->SendCommand("pause");
  } else if (g_strcmp0(method_name, "PlayPause") == 0) {
    self->SendCommand("playPause");
  } else if (g_strcmp0(method_name, "Stop") == 0) {
    self->SendCommand("stop");
  } else if (g_strcmp0(method_name, "Play") == 0) {
    self->SendCommand("play");
  } else if (g_strcmp0(method_name, "Seek") == 0) {
    gint64 offset_us = 0;
    g_variant_get(parameters, "(x)", &offset_us);
    // MPRIS 的偏移量是微秒，且相对于"当前"位置；Dart 侧按毫秒理解。
    self->SendIntCommand("seek", offset_us / 1000);
  } else if (g_strcmp0(method_name, "SetPosition") == 0) {
    const gchar* track_id = nullptr;
    gint64 position_us = 0;
    g_variant_get(parameters, "(&ox)", &track_id, &position_us);
    self->SendIntCommand("setPosition", position_us / 1000);
    self->EmitSeeked(position_us / 1000);
  } else if (g_strcmp0(method_name, "OpenUri") == 0) {
    g_dbus_method_invocation_return_dbus_error(
        invocation, "org.freedesktop.DBus.Error.NotSupported",
        "Koyze 不接受外部 URI 播放。");
    return;
  }
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

GVariant* DesktopMedia::OnGetProperty(GDBusConnection* connection,
                                      const gchar* sender,
                                      const gchar* object_path,
                                      const gchar* interface_name,
                                      const gchar* property_name,
                                      GError** error,
                                      gpointer user_data) {
  auto* self = static_cast<DesktopMedia*>(user_data);
  if (self == nullptr) return nullptr;

  if (g_strcmp0(interface_name, kRootInterface) == 0) {
    if (g_strcmp0(property_name, "Identity") == 0) {
      return g_variant_new_string("Koyze");
    }
    if (g_strcmp0(property_name, "DesktopEntry") == 0) {
      return g_variant_new_string("koyze");
    }
    if (g_strcmp0(property_name, "SupportedUriSchemes") == 0 ||
        g_strcmp0(property_name, "SupportedMimeTypes") == 0) {
      return g_variant_new_strv(nullptr, 0);
    }
    if (g_strcmp0(property_name, "CanRaise") == 0) {
      return g_variant_new_boolean(false);
    }
    return g_variant_new_boolean(false);
  }

  if (g_strcmp0(property_name, "PlaybackStatus") == 0) {
    return g_variant_new_string(self->PlaybackStatus());
  }
  if (g_strcmp0(property_name, "LoopStatus") == 0) {
    return g_variant_new_string("None");
  }
  if (g_strcmp0(property_name, "Shuffle") == 0) {
    return g_variant_new_boolean(false);
  }
  if (g_strcmp0(property_name, "Rate") == 0 ||
      g_strcmp0(property_name, "MinimumRate") == 0 ||
      g_strcmp0(property_name, "MaximumRate") == 0) {
    return g_variant_new_double(1.0);
  }
  if (g_strcmp0(property_name, "Volume") == 0) {
    return g_variant_new_double(1.0);
  }
  if (g_strcmp0(property_name, "Metadata") == 0) {
    return g_variant_ref_sink(self->BuildMetadata());
  }
  if (g_strcmp0(property_name, "Position") == 0) {
    return g_variant_new_int64(self->CurrentPositionMs() * 1000);
  }
  if (g_strcmp0(property_name, "CanGoNext") == 0) {
    return g_variant_new_boolean(self->track_.can_next);
  }
  if (g_strcmp0(property_name, "CanGoPrevious") == 0) {
    return g_variant_new_boolean(self->track_.can_previous);
  }
  if (g_strcmp0(property_name, "CanPlay") == 0 ||
      g_strcmp0(property_name, "CanPause") == 0) {
    return g_variant_new_boolean(self->track_.has_track);
  }
  if (g_strcmp0(property_name, "CanSeek") == 0) {
    return g_variant_new_boolean(self->track_.has_track);
  }
  if (g_strcmp0(property_name, "CanControl") == 0) {
    return g_variant_new_boolean(true);
  }
  g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
              "Unknown property %s", property_name);
  return nullptr;
}

gboolean DesktopMedia::OnSetProperty(GDBusConnection* connection,
                                     const gchar* sender,
                                     const gchar* object_path,
                                     const gchar* interface_name,
                                     const gchar* property_name,
                                     GVariant* value,
                                     GError** error,
                                     gpointer user_data) {
  // 音量、循环、随机播放在 Dart 侧有自己的状态机，原生侧不抢方向盘：
  // 一律接受但忽略写入，避免桌面面板与 App 内设置互相打脸。
  return TRUE;
}

void DesktopMedia::OnNameAcquired(GDBusConnection* connection,
                                  const gchar* name,
                                  gpointer user_data) {}

void DesktopMedia::OnNameLost(GDBusConnection* connection,
                              const gchar* name,
                              gpointer user_data) {
  g_printerr("[koyze] MPRIS name lost: %s\n", name);
}
