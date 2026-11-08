// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

#include "desktop_media.h"

#include <flutter/standard_method_codec.h>

#include <windows.h>

// ISystemMediaTransportControlsInterop 不随 C++/WinRT 投影导出：它是
// Win32 侧的互操作接口，声明在这个 SDK 头里。没有它就没法把 SMTC 绑到
// 具体窗口（GetForWindow），只能绑到进程，多窗口时会串台。
#include <systemmediatransportcontrolsinterop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <algorithm>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

// 通道名与 Linux runner 完全一致。
constexpr char kChannelName[] = "koyze/desktop_media";

std::string Utf8FromWide(const std::wstring& text) {
  if (text.empty()) return std::string();
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, text.c_str(),
                                         static_cast<int>(text.size()),
                                         nullptr, 0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text.c_str(),
                        static_cast<int>(text.size()), out.data(), size,
                        nullptr, nullptr);
  return out;
}

std::wstring WideFromUtf8(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                                         static_cast<int>(text.size()), nullptr,
                                         0);
  if (size <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                        static_cast<int>(text.size()), out.data(), size);
  return out;
}

std::string StringOf(const EncodableMap& map, const char* key,
                     const std::string& fallback = std::string()) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  const auto* text = std::get_if<std::string>(&it->second);
  return text == nullptr ? fallback : *text;
}

int64_t IntOf(const EncodableMap& map, const char* key, int64_t fallback = 0) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&it->second)) return *value;
  if (const auto* value = std::get_if<double>(&it->second)) {
    return static_cast<int64_t>(*value);
  }
  return fallback;
}

bool BoolOf(const EncodableMap& map, const char* key, bool fallback = false) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  const auto* value = std::get_if<bool>(&it->second);
  return value == nullptr ? fallback : *value;
}

}  // namespace

DesktopMedia::DesktopMedia(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  if (messenger == nullptr) return;
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

DesktopMedia::~DesktopMedia() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
  // 先解绑再释放：SMTC 在窗口销毁后仍持有回调，顺序反了会在进程退出时崩。
  ReleaseSmtcObjects();
}

void DesktopMedia::ReleaseSmtcObjects() {
  if (smtc_ != nullptr) {
    auto* controls =
        static_cast<winrt::Windows::Media::SystemMediaTransportControls*>(smtc_);
    try {
      controls->ButtonPressed(nullptr);
      controls->IsEnabled(false);
    } catch (...) {
      // 释放阶段不关心失败。
    }
    delete controls;
    smtc_ = nullptr;
  }
  if (updater_ != nullptr) {
    delete static_cast<
        winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater*>(
        updater_);
    updater_ = nullptr;
  }
  available_ = false;
}

bool DesktopMedia::EnsureInitialized() {
  if (initialized_) return available_;
  initialized_ = true;

  if (window_ == nullptr) return false;

  try {
    // Flutter 的 Windows runner 主线程可能已经进过 COM（引擎自己会用），
    // 重复初始化会抛 RPC_E_CHANGED_MODE。那种情况沿用现有 apartment 即可：
    // SMTC 不强制 STA，只是回调线程会跟着变。
    try {
      winrt::init_apartment(winrt::apartment_type::single_threaded);
    } catch (const winrt::hresult_error&) {
    }

    auto interop = winrt::get_activation_factory<
        winrt::Windows::Media::SystemMediaTransportControls,
        ISystemMediaTransportControlsInterop>();
    winrt::Windows::Media::SystemMediaTransportControls controls{nullptr};
    winrt::check_hresult(interop->GetForWindow(
        window_,
        winrt::guid_of<winrt::Windows::Media::SystemMediaTransportControls>(),
        winrt::put_abi(controls)));

    controls.IsEnabled(false);
    controls.IsPlayEnabled(true);
    controls.IsPauseEnabled(true);
    controls.IsNextEnabled(true);
    controls.IsPreviousEnabled(true);
    controls.IsStopEnabled(true);
    controls.PlaybackStatus(
        winrt::Windows::Media::MediaPlaybackStatus::Closed);

    // 按钮事件从系统线程回到这里，必须切回 UI 线程再碰 channel。
    controls.ButtonPressed(
        [this](const winrt::Windows::Media::SystemMediaTransportControls&,
               const winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs&
                   args) {
          switch (args.Button()) {
            case winrt::Windows::Media::SystemMediaTransportControlsButton::Play:
              SendCommand("play");
              break;
            case winrt::Windows::Media::SystemMediaTransportControlsButton::Pause:
              SendCommand("pause");
              break;
            case winrt::Windows::Media::SystemMediaTransportControlsButton::Next:
              SendCommand("next");
              break;
            case winrt::Windows::Media::SystemMediaTransportControlsButton::Previous:
              SendCommand("previous");
              break;
            case winrt::Windows::Media::SystemMediaTransportControlsButton::Stop:
              SendCommand("stop");
              break;
            default:
              break;
          }
        });

    smtc_ = new winrt::Windows::Media::SystemMediaTransportControls(controls);
    updater_ = new winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater(
        controls.DisplayUpdater());
    available_ = true;
  } catch (const winrt::hresult_error& error) {
    ::OutputDebugStringW(
        (L"[koyze] SMTC unavailable: " + std::wstring(error.message()) + L"\n")
            .c_str());
    available_ = false;
  } catch (...) {
    available_ = false;
  }
  return available_;
}

void DesktopMedia::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "initialize") {
    result->Success();
    return;
  }
  if (method == "update") {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (args != nullptr) ApplyUpdate(*args);
    result->Success();
    return;
  }
  if (method == "clear") {
    ApplyClear();
    result->Success();
    return;
  }
  result->NotImplemented();
}

void DesktopMedia::ApplyUpdate(const EncodableMap& args) {
  if (!EnsureInitialized()) return;

  auto* controls =
      static_cast<winrt::Windows::Media::SystemMediaTransportControls*>(smtc_);
  auto* updater = static_cast<
      winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater*>(
      updater_);
  if (controls == nullptr || updater == nullptr) return;

  const std::string title = StringOf(args, "title");
  const std::string artist = StringOf(args, "artist");
  const std::string album = StringOf(args, "album");
  const std::string artwork = StringOf(args, "artworkPath");
  const bool playing = BoolOf(args, "playing");
  const bool can_next = BoolOf(args, "canGoNext", true);
  const bool can_previous = BoolOf(args, "canGoPrevious", true);

  try {
    updater->Type(winrt::Windows::Media::MediaPlaybackType::Music);
    auto music = updater->MusicProperties();
    if (music.Title() != WideFromUtf8(title)) {
      music.Title(WideFromUtf8(title));
    }
    if (music.Artist() != WideFromUtf8(artist)) {
      music.Artist(WideFromUtf8(artist));
    }
    if (music.AlbumTitle() != WideFromUtf8(album)) {
      music.AlbumTitle(WideFromUtf8(album));
    }

    // 封面是本地缓存文件，直接读磁盘，不再走一次网络。
    if (!artwork.empty() && artwork != last_artwork_) {
      LoadThumbnail(WideFromUtf8(artwork));
      last_artwork_ = artwork;
    }
    updater->Update();

    controls->PlaybackStatus(
        playing ? winrt::Windows::Media::MediaPlaybackStatus::Playing
                : winrt::Windows::Media::MediaPlaybackStatus::Paused);
    controls->IsEnabled(true);
    controls->IsNextEnabled(can_next);
    controls->IsPreviousEnabled(can_previous);
  } catch (const winrt::hresult_error&) {
    // 系统拒绝写入（例如面板被组策略关掉）时不该影响播放。
  }
}

void DesktopMedia::ApplyClear() {
  if (!available_) return;
  auto* controls =
      static_cast<winrt::Windows::Media::SystemMediaTransportControls*>(smtc_);
  auto* updater = static_cast<
      winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater*>(
      updater_);
  if (controls == nullptr || updater == nullptr) return;

  try {
    controls->PlaybackStatus(winrt::Windows::Media::MediaPlaybackStatus::Closed);
    updater->ClearAll();
    controls->IsEnabled(false);
  } catch (const winrt::hresult_error&) {
  }
  last_artwork_.clear();
  last_title_.clear();
  last_artist_.clear();
}

void DesktopMedia::LoadThumbnail(const std::wstring& path) {
  auto* updater = static_cast<
      winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater*>(
      updater_);
  if (updater == nullptr || path.empty()) return;

  // 用 file:// URI 让系统自己去读图，全程不阻塞 UI 线程。
  //
  // 这里踩过两个坑：
  //  - StorageFile::GetFileFromPathAsync(...).get() 会在 UI 线程上死锁，
  //    因为它等的是同一线程继续泵消息才能完成的异步操作；
  //  - DataWriter + StoreAsync().get() 同理。
  // 封面只有几十 KB，但一旦死锁整个界面就卡住，代价完全不成比例。
  try {
    std::wstring normalized = path;
    std::replace(normalized.begin(), normalized.end(), L'\\', L'/');
    if (normalized.rfind(L"file:///", 0) != 0) {
      normalized = L"file:///" + normalized;
    }
    updater->Thumbnail(
        winrt::Windows::Storage::Streams::RandomAccessStreamReference::
            CreateFromUri(winrt::Windows::Foundation::Uri(normalized)));
  } catch (const winrt::hresult_error&) {
    // 封面读不到就只是没有封面，不要连元数据一起放弃。
  }
}

void DesktopMedia::SendCommand(const std::string& command) {
  if (!channel_) return;
  channel_->InvokeMethod(command,
                         std::make_unique<EncodableValue>());
}

void DesktopMedia::SendIntCommand(const std::string& command, int64_t value) {
  if (!channel_) return;
  channel_->InvokeMethod(command, std::make_unique<EncodableValue>(value));
}
