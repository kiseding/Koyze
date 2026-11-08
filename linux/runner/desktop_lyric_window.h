// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

#ifndef RUNNER_DESKTOP_LYRIC_WINDOW_H_
#define RUNNER_DESKTOP_LYRIC_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <string>

// 桌面歌词窗（Linux）。
//
// 一个无边框、置顶、不抢焦点、不进任务栏的小窗，只画两行歌词：上一行暗、
// 当前行亮。它跟主窗共享同一个 GTK application，但**不是** GtkApplicationWindow
// ——那会把应用当成有第二个主窗口，任务栏出现两个条目。
//
// 交互只做三件事：拖动移动、滚轮调字号、双击回正。拖动后的位置回报给 Dart，
// 由它负责持久化。
class DesktopLyricWindow {
 public:
  explicit DesktopLyricWindow(FlMethodChannel* channel);
  ~DesktopLyricWindow();

  DesktopLyricWindow(const DesktopLyricWindow&) = delete;
  DesktopLyricWindow& operator=(const DesktopLyricWindow&) = delete;

  // Dart 侧方法：show / hide / update / setStyle / setPosition.
  void HandleMethodCall(FlMethodCall* method_call);

  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data);

  // 是否已经建过窗。没建过时收到 update 不会顺便建窗——用户没开这个功能。
  bool visible() const { return window_ != nullptr; }

 private:
  void EnsureWindow();
  void DestroyWindow();
  void ApplyText(const std::string& current, const std::string& next);
  void ApplyPosition(FlValue* args);
  void ApplyStyle(int64_t font_size, double opacity, bool locked);
  void Redraw();
  void EmitPosition();
  void SendEvent(const char* event, FlValue* payload);

  // GTK 回调。C 函数指针拿不到 this，统一走 user_data。
  static gboolean OnDraw(GtkWidget* widget, cairo_t* cr, gpointer user_data);
  static gboolean OnButtonPress(GtkWidget* widget, GdkEventButton* event,
                                gpointer user_data);
  static gboolean OnButtonRelease(GtkWidget* widget, GdkEventButton* event,
                                  gpointer user_data);
  static gboolean OnMotion(GtkWidget* widget, GdkEventMotion* event,
                           gpointer user_data);
  static gboolean OnScroll(GtkWidget* widget, GdkEventScroll* event,
                           gpointer user_data);
  static gboolean OnDelete(GtkWidget* widget, GdkEvent* event,
                           gpointer user_data);

  FlMethodChannel* channel_ = nullptr;  // owned

  GtkWidget* window_ = nullptr;
  GtkWidget* area_ = nullptr;

  std::string current_text_;
  std::string next_text_;

  int font_size_ = 28;
  double opacity_ = 0.9;
  // 锁定后鼠标穿透，拖动和滚轮都失效——打游戏或看视频时不想被误拖。
  bool locked_ = false;

  bool dragging_ = false;
  double drag_x_ = 0;
  double drag_y_ = 0;
};

#endif  // RUNNER_DESKTOP_LYRIC_WINDOW_H_
