// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

#include "desktop_lyric_window.h"

#include <cairo/cairo.h>
#include <pango/pangocairo.h>

#include <algorithm>
#include <cmath>

namespace {

// 通道由 my_application.cc 创建后传给本类，这里不再重复定义常量。
constexpr int kDefaultWidth = 720;
constexpr int kDefaultHeight = 116;
constexpr int kMinFontSize = 16;
constexpr int kMaxFontSize = 72;

std::string StringOf(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return std::string();
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return std::string();
  }
  const gchar* text = fl_value_get_string(value);
  return text == nullptr ? std::string() : std::string(text);
}

int64_t IntOf(FlValue* map, const char* key, int64_t fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
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

bool BoolOf(FlValue* map, const char* key, bool fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

// 用 Pango 画一行居中文字，返回实际占用的高度。
//
// 单独抽出来是因为两行（当前行 / 下一行）除了字号和颜色完全一样，重复写两遍
// 只会让两处的换行策略慢慢漂移。
double DrawLine(cairo_t* cr, const std::string& text, double center_y,
                int font_size, double alpha, bool bold, int width) {
  if (text.empty()) return 0;

  PangoLayout* layout = pango_cairo_create_layout(cr);
  PangoFontDescription* desc = pango_font_description_new();
  pango_font_description_set_family(desc, "Sans");
  pango_font_description_set_absolute_size(desc,
                                           font_size * PANGO_SCALE);
  pango_font_description_set_weight(
      desc, bold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL);
  pango_layout_set_font_description(layout, desc);
  pango_layout_set_text(layout, text.c_str(), -1);
  pango_layout_set_width(layout, width * PANGO_SCALE);
  pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER);
  // 歌词一行放不下就截断，不要折行——桌面歌词窗只有一行的高度。
  pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
  // 限制成一行：pango_layout_set_height 传负值是「行数」语义（正值为像素
  // 高度），配合上面的 ellipsize 就能做到「超出即省略」而不是折行。
  pango_layout_set_height(layout, -1);

  int text_width = 0;
  int text_height = 0;
  pango_layout_get_pixel_size(layout, &text_width, &text_height);

  cairo_save(cr);
  cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, alpha);
  cairo_move_to(cr, 0, center_y - text_height / 2.0);
  pango_cairo_show_layout(cr, layout);
  cairo_restore(cr);

  pango_font_description_free(desc);
  g_object_unref(layout);
  return text_height;
}

}  // namespace

DesktopLyricWindow::DesktopLyricWindow(FlMethodChannel* channel) {
  channel_ = channel == nullptr ? nullptr : FL_METHOD_CHANNEL(g_object_ref(channel));
}

DesktopLyricWindow::~DesktopLyricWindow() {
  DestroyWindow();
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }
}

void DesktopLyricWindow::EnsureWindow() {
  if (window_ != nullptr) return;

  // GTK_WINDOW_POPUP：无边框、不接受焦点、窗口管理器不接管。用它而不是
  // GTK_WINDOW_TOPLEVEL + 一堆 hint，是因为 popup 天然不会进任务栏和
  // alt-tab 列表，正好是桌面歌词要的语义。
  window_ = gtk_window_new(GTK_WINDOW_POPUP);
  gtk_window_set_default_size(GTK_WINDOW(window_), kDefaultWidth, kDefaultHeight);
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE);
  gtk_window_set_focus_on_map(GTK_WINDOW(window_), FALSE);
  // 每像素透明：歌词窗背景必须完全透，否则会出现一块黑底。
  gtk_widget_set_app_paintable(window_, TRUE);
  GdkScreen* screen = gtk_widget_get_screen(window_);
  if (screen != nullptr) {
    GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
    if (visual != nullptr) {
      gtk_widget_set_visual(window_, visual);
    }
  }

  area_ = gtk_drawing_area_new();
  gtk_widget_set_size_request(area_, kDefaultWidth, kDefaultHeight);
  gtk_container_add(GTK_CONTAINER(window_), area_);

  gtk_widget_add_events(area_, GDK_BUTTON_PRESS_MASK |
                                   GDK_BUTTON_RELEASE_MASK |
                                   GDK_POINTER_MOTION_MASK |
                                   GDK_SCROLL_MASK |
                                   GDK_SMOOTH_SCROLL_MASK);

  g_signal_connect(area_, "draw", G_CALLBACK(OnDraw), this);
  g_signal_connect(area_, "button-press-event", G_CALLBACK(OnButtonPress), this);
  g_signal_connect(area_, "button-release-event", G_CALLBACK(OnButtonRelease),
                   this);
  g_signal_connect(area_, "motion-notify-event", G_CALLBACK(OnMotion), this);
  g_signal_connect(area_, "scroll-event", G_CALLBACK(OnScroll), this);
  g_signal_connect(window_, "delete-event", G_CALLBACK(OnDelete), this);

  // 放到屏幕底部居中，离任务栏留一点距离。
  GdkDisplay* display = gtk_widget_get_display(window_);
  if (display != nullptr) {
    GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
    if (monitor == nullptr) monitor = gdk_display_get_monitor(display, 0);
    if (monitor != nullptr) {
      GdkRectangle workarea = {0, 0, 0, 0};
      gdk_monitor_get_workarea(monitor, &workarea);
      if (workarea.width > 0) {
        const int x = workarea.x + (workarea.width - kDefaultWidth) / 2;
        const int y = workarea.y + workarea.height - kDefaultHeight - 48;
        gtk_window_move(GTK_WINDOW(window_), x, y);
      }
    }
  }

  gtk_widget_show_all(window_);
}

void DesktopLyricWindow::DestroyWindow() {
  if (window_ == nullptr) return;
  gtk_widget_destroy(window_);
  window_ = nullptr;
  area_ = nullptr;
  dragging_ = false;
}

void DesktopLyricWindow::HandleMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(GError) error = nullptr;

  if (g_strcmp0(method, "show") == 0) {
    EnsureWindow();
    ApplyPosition(args);
    Redraw();
    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }
  if (g_strcmp0(method, "hide") == 0) {
    DestroyWindow();
    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }
  if (g_strcmp0(method, "update") == 0) {
    ApplyText(StringOf(args, "current"), StringOf(args, "next"));
    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }
  if (g_strcmp0(method, "setPosition") == 0) {
    ApplyPosition(args);
    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }
  if (g_strcmp0(method, "setStyle") == 0) {
    ApplyStyle(IntOf(args, "fontSize", font_size_),
               fl_value_get_type(args) == FL_VALUE_TYPE_MAP &&
                       fl_value_lookup_string(args, "opacity") != nullptr
                   ? fl_value_get_float(
                         fl_value_lookup_string(args, "opacity"))
                   : opacity_,
               BoolOf(args, "locked", locked_));
    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }
  fl_method_call_respond_not_implemented(method_call, &error);
}

void DesktopLyricWindow::ApplyPosition(FlValue* args) {
  if (window_ == nullptr) return;
  const auto x = IntOf(args, "x", G_MININT);
  const auto y = IntOf(args, "y", G_MININT);
  if (x == G_MININT || y == G_MININT) return;
  gtk_window_move(GTK_WINDOW(window_), static_cast<int>(x),
                  static_cast<int>(y));
}

void DesktopLyricWindow::ApplyText(const std::string& current,
                                   const std::string& next) {
  if (current == current_text_ && next == next_text_) return;
  current_text_ = current;
  next_text_ = next;
  // 文字变了才重绘；Dart 侧每秒推一次进度，但文字不变时那次推送不该触发重绘。
  Redraw();
}

void DesktopLyricWindow::ApplyStyle(int64_t font_size, double opacity,
                                    bool locked) {
  const int clamped = static_cast<int>(
      std::clamp<int64_t>(font_size, kMinFontSize, kMaxFontSize));
  const double clamped_opacity = std::clamp(opacity, 0.15, 1.0);
  const bool changed = clamped != font_size_ ||
                       std::abs(clamped_opacity - opacity_) > 0.001 ||
                       locked != locked_;
  font_size_ = clamped;
  opacity_ = clamped_opacity;
  locked_ = locked;

  if (window_ != nullptr) {
    // 锁定后整窗穿透，鼠标事件不再落到这里。
    GdkWindow* gdk_window = gtk_widget_get_window(window_);
    if (gdk_window != nullptr) {
      cairo_region_t* region = nullptr;
      if (locked_) {
        region = cairo_region_create();
      }
      gdk_window_input_shape_combine_region(gdk_window, region, 0, 0);
      if (region != nullptr) cairo_region_destroy(region);
    }
  }
  if (changed) Redraw();
}

void DesktopLyricWindow::Redraw() {
  if (area_ != nullptr) gtk_widget_queue_draw(area_);
}

void DesktopLyricWindow::EmitPosition() {
  if (window_ == nullptr) return;
  gint x = 0;
  gint y = 0;
  gtk_window_get_position(GTK_WINDOW(window_), &x, &y);
  g_autoptr(FlValue) payload = fl_value_new_map();
  fl_value_set_string_take(payload, "x", fl_value_new_int(x));
  fl_value_set_string_take(payload, "y", fl_value_new_int(y));
  SendEvent("position", payload);
}

void DesktopLyricWindow::SendEvent(const char* event, FlValue* payload) {
  if (channel_ == nullptr) return;
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "event", fl_value_new_string(event));
  if (payload != nullptr) {
    fl_value_set_string_take(map, "payload", fl_value_ref(payload));
  }
  fl_method_channel_invoke_method(channel_, "event", map, nullptr, nullptr,
                                  nullptr);
}

gboolean DesktopLyricWindow::OnDraw(GtkWidget* widget, cairo_t* cr,
                                    gpointer user_data) {
  auto* self = static_cast<DesktopLyricWindow*>(user_data);
  if (self == nullptr) return FALSE;

  GtkAllocation allocation;
  gtk_widget_get_allocation(widget, &allocation);
  const int width = allocation.width;
  const int height = allocation.height;
  if (width <= 0 || height <= 0) return FALSE;

  // 透明底 + 一层很淡的黑，保证浅色壁纸上白字也看得清。
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cr, 0, 0, 0, 0);
  cairo_paint(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.28 * self->opacity_);
  const double radius = 14;
  cairo_new_sub_path(cr);
  cairo_arc(cr, width - radius, radius, radius, -M_PI / 2, 0);
  cairo_arc(cr, width - radius, height - radius, radius, 0, M_PI / 2);
  cairo_arc(cr, radius, height - radius, radius, M_PI / 2, M_PI);
  cairo_arc(cr, radius, radius, radius, M_PI, 3 * M_PI / 2);
  cairo_close_path(cr);
  cairo_fill(cr);

  // 当前行占上方 2/3，下一行小字压在底部做预告。
  DrawLine(cr, self->current_text_, height * 0.42, self->font_size_,
           self->opacity_, true, width);
  DrawLine(cr, self->next_text_, height * 0.82,
           std::max(kMinFontSize, self->font_size_ * 3 / 5),
           self->opacity_ * 0.5, false, width);
  return TRUE;
}

gboolean DesktopLyricWindow::OnButtonPress(GtkWidget* widget,
                                           GdkEventButton* event,
                                           gpointer user_data) {
  auto* self = static_cast<DesktopLyricWindow*>(user_data);
  if (self == nullptr) return FALSE;

  if (event->button == 1) {
    self->dragging_ = true;
    self->drag_x_ = event->x_root;
    self->drag_y_ = event->y_root;
    return TRUE;
  }
  if (event->button == 2 && self->window_ != nullptr) {
    // 中键回到屏幕默认位置。
    GdkDisplay* display = gtk_widget_get_display(self->window_);
    GdkMonitor* monitor = display == nullptr
        ? nullptr
        : gdk_display_get_primary_monitor(display);
    if (monitor == nullptr && display != nullptr) {
      monitor = gdk_display_get_monitor(display, 0);
    }
    if (monitor != nullptr) {
      GdkRectangle workarea = {0, 0, 0, 0};
      gdk_monitor_get_workarea(monitor, &workarea);
      gtk_window_move(GTK_WINDOW(self->window_),
                      workarea.x + (workarea.width - kDefaultWidth) / 2,
                      workarea.y + workarea.height - kDefaultHeight - 48);
    }
    self->EmitPosition();
    return TRUE;
  }
  return FALSE;
}

gboolean DesktopLyricWindow::OnButtonRelease(GtkWidget* widget,
                                             GdkEventButton* event,
                                             gpointer user_data) {
  auto* self = static_cast<DesktopLyricWindow*>(user_data);
  if (self == nullptr) return FALSE;
  if (event->button == 1 && self->dragging_) {
    self->dragging_ = false;
    // 拖动结束时才回报位置，拖动过程中不回报：否则 Dart 侧每秒写一次
    // shared_preferences，一次拖动就是几十次磁盘写入。
    self->EmitPosition();
    return TRUE;
  }
  return FALSE;
}

gboolean DesktopLyricWindow::OnMotion(GtkWidget* widget, GdkEventMotion* event,
                                      gpointer user_data) {
  auto* self = static_cast<DesktopLyricWindow*>(user_data);
  if (self == nullptr || !self->dragging_ || self->window_ == nullptr) {
    return FALSE;
  }
  gint x = 0;
  gint y = 0;
  gtk_window_get_position(GTK_WINDOW(self->window_), &x, &y);
  gtk_window_move(GTK_WINDOW(self->window_),
                  x + static_cast<int>(event->x_root - self->drag_x_),
                  y + static_cast<int>(event->y_root - self->drag_y_));
  self->drag_x_ = event->x_root;
  self->drag_y_ = event->y_root;
  return TRUE;
}

gboolean DesktopLyricWindow::OnScroll(GtkWidget* widget, GdkEventScroll* event,
                                      gpointer user_data) {
  auto* self = static_cast<DesktopLyricWindow*>(user_data);
  if (self == nullptr) return FALSE;
  int delta = 0;
  if (event->direction == GDK_SCROLL_UP) {
    delta = 2;
  } else if (event->direction == GDK_SCROLL_DOWN) {
    delta = -2;
  }
  if (delta == 0) return FALSE;
  self->ApplyStyle(self->font_size_ + delta, self->opacity_, self->locked_);
  g_autoptr(FlValue) payload = fl_value_new_map();
  fl_value_set_string_take(payload, "fontSize",
                           fl_value_new_int(self->font_size_));
  self->SendEvent("style", payload);
  return TRUE;
}

gboolean DesktopLyricWindow::OnDelete(GtkWidget* widget, GdkEvent* event,
                                      gpointer user_data) {
  auto* self = static_cast<DesktopLyricWindow*>(user_data);
  if (self != nullptr) self->SendEvent("closed", nullptr);
  return TRUE;  // 不销毁，由 Dart 侧决定是隐藏还是保留。
}

void DesktopLyricWindow::OnMethodCall(FlMethodChannel* channel,
                                      FlMethodCall* method_call,
                                      gpointer user_data) {
  auto* self = static_cast<DesktopLyricWindow*>(user_data);
  if (self == nullptr) return;
  self->HandleMethodCall(method_call);
}
