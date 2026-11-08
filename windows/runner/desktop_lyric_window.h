// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

#ifndef RUNNER_DESKTOP_LYRIC_WINDOW_H_
#define RUNNER_DESKTOP_LYRIC_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

class DesktopLyricWindow {
 public:
  explicit DesktopLyricWindow(flutter::BinaryMessenger* messenger);
  ~DesktopLyricWindow();

  DesktopLyricWindow(const DesktopLyricWindow&) = delete;
  DesktopLyricWindow& operator=(const DesktopLyricWindow&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool EnsureWindow();
  void DestroyWindow();
  void ApplyUpdate(const flutter::EncodableMap& args);
  void ApplyStyle(const flutter::EncodableMap& args);
  void ApplyPosition(const flutter::EncodableMap& args);
  void Redraw();
  void EmitEvent(const char* event,
                 const flutter::EncodableMap* payload = nullptr);
  void EmitPosition();
  void Draw();
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_ = nullptr;
  std::wstring current_;
  std::wstring next_;
  int font_size_ = 28;
  double opacity_ = 0.9;
  bool locked_ = false;
  bool dragging_ = false;
  POINT drag_origin_{};
  POINT window_origin_{};
};

#endif  // RUNNER_DESKTOP_LYRIC_WINDOW_H_
