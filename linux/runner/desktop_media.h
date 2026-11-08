// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

#ifndef RUNNER_DESKTOP_MEDIA_H_
#define RUNNER_DESKTOP_MEDIA_H_

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

#include <string>

// Linux 系统媒体面板集成：实现 MPRIS（org.mpris.MediaPlayer2.koyze）。
//
// GNOME、KDE、Playerctl、锁屏、蓝牙耳机按键都通过 MPRIS 找播放器，而不是
// 去猜窗口标题。没有这一层，Linux 上的「上一首/下一首」物理按键和顶栏媒体
// 小组件都不会把 Koyze 当成播放器。
//
// 数据流是双向的：Dart 侧把当前曲目与播放状态推下来（update/clear），
// 系统侧的控制请求（播放/暂停/切歌/拖动）通过同一个 method channel 回发给
// Dart，永远不在原生侧直接操作播放器。
class DesktopMedia final {
 public:
  explicit DesktopMedia(FlMethodChannel* channel);
  ~DesktopMedia();

  DesktopMedia(const DesktopMedia&) = delete;
  DesktopMedia& operator=(const DesktopMedia&) = delete;

  // 处理 Dart 发来的方法调用。
  void HandleMethodCall(FlMethodCall* method_call);

  // 暴露给 MPRIS 方法处理的命令回发（播放/暂停/切歌/拖动）。
  void SendCommand(const char* command);
  void SendIntCommand(const char* command, int64_t value);

  // GLib / Flutter 的 C 回调，必须对注册它的代码可见。
  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data);
  static void OnPlayerMethodCall(GDBusConnection* connection,
                                 const gchar* sender,
                                 const gchar* object_path,
                                 const gchar* interface_name,
                                 const gchar* method_name,
                                 GVariant* parameters,
                                 GDBusMethodInvocation* invocation,
                                 gpointer user_data);
  static GVariant* OnGetProperty(GDBusConnection* connection,
                                 const gchar* sender,
                                 const gchar* object_path,
                                 const gchar* interface_name,
                                 const gchar* property_name,
                                 GError** error,
                                 gpointer user_data);
  static gboolean OnSetProperty(GDBusConnection* connection,
                                const gchar* sender,
                                const gchar* object_path,
                                const gchar* interface_name,
                                const gchar* property_name,
                                GVariant* value,
                                GError** error,
                                gpointer user_data);

 private:
  struct Track {
    bool has_track = false;
    std::string identity;
    std::string title;
    std::string artist;
    std::string album;
    std::string artwork_path;
    int64_t duration_ms = 0;
    int64_t position_ms = 0;
    bool playing = false;
    bool can_next = false;
    bool can_previous = false;
    // g_get_monotonic_time() 采样点，用于把 position_ms 外推到「现在」。
    int64_t sampled_us = 0;
  };

  void EnsureRegistered();
  void UpdateFromMap(FlValue* args);
  void ClearTrack();
  void NotifyPropertiesChanged(bool include_metadata);
  void EmitSeeked(int64_t position_ms);

  int64_t CurrentPositionMs() const;
  const char* PlaybackStatus() const;
  const char* TrackObjectPath() const;
  GVariant* BuildMetadata() const;

  static void OnNameAcquired(GDBusConnection* connection,
                             const gchar* name,
                             gpointer user_data);
  static void OnNameLost(GDBusConnection* connection,
                         const gchar* name,
                         gpointer user_data);

  FlMethodChannel* channel_ = nullptr;  // owned
  GDBusConnection* connection_ = nullptr;
  GDBusNodeInfo* node_info_ = nullptr;
  guint root_registration_ = 0;
  guint player_registration_ = 0;
  guint owner_id_ = 0;
  bool registered_ = false;
  Track track_;
  std::string track_path_;
};

#endif  // RUNNER_DESKTOP_MEDIA_H_
