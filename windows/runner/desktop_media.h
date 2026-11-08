// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

#ifndef RUNNER_DESKTOP_MEDIA_H_
#define RUNNER_DESKTOP_MEDIA_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

// Windows 系统媒体面板（SMTC）集成。
//
// 与 Linux runner 的 MPRIS 实现共用同一个通道名（koyze/desktop_media）和同一
// 套方法语义，Dart 侧因此只需要一份 DesktopMediaSession，不用按平台分叉。
//
// SMTC 与 MPRIS 的一处关键差异：Windows 的媒体面板是按窗口注册的
// （GetForWindow），而不是按进程名。这意味着窗口销毁时必须显式解绑，
// 否则下一次启动会被系统认为"上一个实例还在"而拒绝显示按钮。
class DesktopMedia {
 public:
  DesktopMedia(flutter::BinaryMessenger* messenger, HWND window);
  ~DesktopMedia();

  DesktopMedia(const DesktopMedia&) = delete;
  DesktopMedia& operator=(const DesktopMedia&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ApplyUpdate(const flutter::EncodableMap& args);
  void ApplyClear();
  void SendCommand(const std::string& command);
  void SendIntCommand(const std::string& command, int64_t value);
  void LoadThumbnail(const std::wstring& path);

  // 拿不到 SMTC（旧系统、被组策略禁用、COM 初始化失败）时置 false，
  // 之后所有调用直接返回，不再反复尝试。
  bool EnsureInitialized();

  // 解绑并释放 C++/WinRT 对象。析构与窗口销毁都会走到这里。
  void ReleaseSmtcObjects();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // 用 void* 持有 C++/WinRT 对象：本头文件不引入 <winrt/...>，
  // 这样任何编译单元 include 它都不必开启 C++/WinRT 的异常设置。
  //
  // 实际指向 .cc 里的 SmtcState。C++/WinRT 的投影类型删除了 operator new
  // （它们只能由 ABI 工厂产出），所以不能 new 单个对象，只能把要保存的几个
  // 对象放进一个普通结构体，再对那层壳分配。
  void* state_ = nullptr;
  HWND window_ = nullptr;

  bool initialized_ = false;
  bool available_ = false;

  // 上一次写入的值，用来跳过没变化的推送。SMTC 每次写入都会走
  // RPC 到系统进程，播放中每秒一次已经够多了。
  std::string last_title_;
  std::string last_artist_;
  std::string last_album_;
  std::string last_artwork_;
  bool last_can_next_ = false;
  bool last_can_previous_ = false;
};

#endif  // RUNNER_DESKTOP_MEDIA_H_
