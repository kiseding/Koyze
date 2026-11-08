// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

#include "desktop_lyric_window.h"

#include <windowsx.h>

#include <algorithm>
#include <string>

namespace {

constexpr wchar_t kWindowClass[] = L"KoyzeDesktopLyricWindow";
constexpr char kChannelName[] = "koyze/desktop_lyric";
constexpr int kWindowWidth = 720;
constexpr int kWindowHeight = 116;
constexpr int kMinFontSize = 16;
constexpr int kMaxFontSize = 72;

std::wstring WideFromUtf8(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                       static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), size);
  return result;
}

std::string StringOf(const flutter::EncodableMap& map, const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  if (found == map.end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value == nullptr ? std::string() : *value;
}

int64_t IntOf(const flutter::EncodableMap& map, const char* key,
              int64_t fallback) {
  const auto found = map.find(flutter::EncodableValue(key));
  if (found == map.end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&found->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&found->second)) return *value;
  if (const auto* value = std::get_if<double>(&found->second)) {
    return static_cast<int64_t>(*value);
  }
  return fallback;
}

bool BoolOf(const flutter::EncodableMap& map, const char* key, bool fallback) {
  const auto found = map.find(flutter::EncodableValue(key));
  if (found == map.end()) return fallback;
  const auto* value = std::get_if<bool>(&found->second);
  return value == nullptr ? fallback : *value;
}

void DrawLine(HDC dc, const std::wstring& text, RECT rect, int font_size,
              BYTE brightness, bool bold) {
  if (text.empty()) return;
  const int height = -MulDiv(font_size, GetDeviceCaps(dc, LOGPIXELSY), 72);
  HFONT font = CreateFontW(height, 0, 0, 0, bold ? FW_BOLD : FW_NORMAL, FALSE,
                           FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
  if (font == nullptr) return;
  const auto old_font = SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  RECT shadow = rect;
  OffsetRect(&shadow, 1, 1);
  SetTextColor(dc, RGB(0, 0, 0));
  DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &shadow,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
  SetTextColor(dc, RGB(brightness, brightness, brightness));
  DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
  SelectObject(dc, old_font);
  DeleteObject(font);
}

}  // namespace

DesktopLyricWindow::DesktopLyricWindow(flutter::BinaryMessenger* messenger) {
  if (messenger == nullptr) return;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

DesktopLyricWindow::~DesktopLyricWindow() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  DestroyWindow();
}

bool DesktopLyricWindow::EnsureWindow() {
  if (window_ != nullptr) return true;
  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.style = CS_HREDRAW | CS_VREDRAW;
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window_class.hbrBackground = nullptr;
  window_class.lpszClassName = kWindowClass;
  if (!RegisterClassExW(&window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }

  const int x = (GetSystemMetrics(SM_CXSCREEN) - kWindowWidth) / 2;
  const int y = GetSystemMetrics(SM_CYSCREEN) - kWindowHeight - 72;
  window_ = CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kWindowClass, L"Koyze Lyrics", WS_POPUP, x, y, kWindowWidth, kWindowHeight,
      nullptr, nullptr, GetModuleHandleW(nullptr), this);
  if (window_ == nullptr) return false;
  SetLayeredWindowAttributes(
      window_, RGB(0, 0, 0), static_cast<BYTE>(opacity_ * 255),
      LWA_COLORKEY | LWA_ALPHA);
  ShowWindow(window_, SW_SHOWNOACTIVATE);
  Redraw();
  return true;
}

void DesktopLyricWindow::DestroyWindow() {
  if (window_ == nullptr) return;
  HWND window = window_;
  window_ = nullptr;
  ::DestroyWindow(window);
  dragging_ = false;
}

void DesktopLyricWindow::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  if (call.method_name() == "show") {
    if (!EnsureWindow()) {
      result->Error("window_creation_failed", "Could not create lyric window");
      return;
    }
    if (args != nullptr) ApplyPosition(*args);
    Redraw();
    result->Success();
    return;
  }
  if (call.method_name() == "hide") {
    DestroyWindow();
    result->Success();
    return;
  }
  if (call.method_name() == "update") {
    if (args != nullptr) ApplyUpdate(*args);
    result->Success();
    return;
  }
  if (call.method_name() == "setStyle") {
    if (args != nullptr) ApplyStyle(*args);
    result->Success();
    return;
  }
  if (call.method_name() == "setPosition") {
    if (args != nullptr) ApplyPosition(*args);
    result->Success();
    return;
  }
  result->NotImplemented();
}

void DesktopLyricWindow::ApplyUpdate(const flutter::EncodableMap& args) {
  const auto current = WideFromUtf8(StringOf(args, "current"));
  const auto next = WideFromUtf8(StringOf(args, "next"));
  if (current_ == current && next_ == next) return;
  current_ = current;
  next_ = next;
  Redraw();
}

void DesktopLyricWindow::ApplyStyle(const flutter::EncodableMap& args) {
  const int64_t requested = IntOf(args, "fontSize", font_size_);
  font_size_ = static_cast<int>(std::clamp<int64_t>(requested, kMinFontSize,
                                                    kMaxFontSize));
  const auto found = args.find(flutter::EncodableValue("opacity"));
  if (found != args.end()) {
    if (const auto* value = std::get_if<double>(&found->second)) {
      opacity_ = std::clamp(*value, 0.15, 1.0);
    }
  }
  locked_ = BoolOf(args, "locked", locked_);
  if (window_ != nullptr) {
    LONG_PTR style = GetWindowLongPtrW(window_, GWL_EXSTYLE);
    style = locked_ ? (style | WS_EX_TRANSPARENT) : (style & ~WS_EX_TRANSPARENT);
    SetWindowLongPtrW(window_, GWL_EXSTYLE, style);
    SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    SetLayeredWindowAttributes(
        window_, RGB(0, 0, 0), static_cast<BYTE>(opacity_ * 255),
        LWA_COLORKEY | LWA_ALPHA);
  }
  Redraw();
}

void DesktopLyricWindow::ApplyPosition(const flutter::EncodableMap& args) {
  if (window_ == nullptr) return;
  const auto x = IntOf(args, "x", LONG_MIN);
  const auto y = IntOf(args, "y", LONG_MIN);
  if (x == LONG_MIN || y == LONG_MIN) return;
  SetWindowPos(window_, HWND_TOPMOST, static_cast<int>(x), static_cast<int>(y),
               0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
}

void DesktopLyricWindow::Redraw() {
  if (window_ != nullptr) InvalidateRect(window_, nullptr, TRUE);
}

void DesktopLyricWindow::EmitEvent(const char* event,
                                   const flutter::EncodableMap* payload) {
  if (!channel_) return;
  flutter::EncodableMap message;
  message[flutter::EncodableValue("event")] = flutter::EncodableValue(event);
  if (payload != nullptr) {
    message[flutter::EncodableValue("payload")] = flutter::EncodableValue(*payload);
  }
  channel_->InvokeMethod("event", std::make_unique<flutter::EncodableValue>(message));
}

void DesktopLyricWindow::EmitPosition() {
  if (window_ == nullptr) return;
  RECT rect{};
  if (!GetWindowRect(window_, &rect)) return;
  flutter::EncodableMap payload;
  // EncodableValue 的变体里只有 int32/int64/double，而 RECT 的成员是 LONG
  // （Windows 上是 long）。不做窄化转换的话，变体构造会因为多个候选同样可
  // 转换而报歧义。
  payload[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.left));
  payload[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.top));
  EmitEvent("position", &payload);
}

void DesktopLyricWindow::Draw() {
  if (window_ == nullptr) return;
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(window_, &paint);
  RECT client{};
  GetClientRect(window_, &client);
  HBRUSH clear = CreateSolidBrush(RGB(0, 0, 0));
  FillRect(dc, &client, clear);
  DeleteObject(clear);
  const int height = client.bottom - client.top;
  RECT current{12, 8, client.right - 12, height * 2 / 3};
  RECT next{12, height * 2 / 3, client.right - 12, height - 8};
  DrawLine(dc, current_, current, font_size_,
           static_cast<BYTE>(opacity_ * 255), true);
  DrawLine(dc, next_, next, std::max(kMinFontSize, font_size_ * 3 / 5),
           static_cast<BYTE>(opacity_ * 150), false);
  EndPaint(window_, &paint);
}

LRESULT CALLBACK DesktopLyricWindow::WindowProc(HWND hwnd, UINT message,
                                                 WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<DesktopLyricWindow*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = static_cast<DesktopLyricWindow*>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (self == nullptr) return DefWindowProcW(hwnd, message, wparam, lparam);

  switch (message) {
    case WM_PAINT:
      self->Draw();
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_LBUTTONDOWN:
      if (!self->locked_) {
        self->dragging_ = true;
        SetCapture(hwnd);
        GetCursorPos(&self->drag_origin_);
        RECT rect{};
        GetWindowRect(hwnd, &rect);
        self->window_origin_ = {rect.left, rect.top};
      }
      return 0;
    case WM_MOUSEMOVE:
      if (self->dragging_) {
        POINT cursor{};
        GetCursorPos(&cursor);
        SetWindowPos(hwnd, HWND_TOPMOST,
                     self->window_origin_.x + cursor.x - self->drag_origin_.x,
                     self->window_origin_.y + cursor.y - self->drag_origin_.y,
                     0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (self->dragging_) {
        self->dragging_ = false;
        ReleaseCapture();
        self->EmitPosition();
      }
      return 0;
    case WM_MOUSEWHEEL: {
      if (self->locked_) return 0;
      const int delta = GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? 2 : -2;
      self->font_size_ = std::clamp(self->font_size_ + delta,
                                    kMinFontSize, kMaxFontSize);
      self->Redraw();
      flutter::EncodableMap payload;
      payload[flutter::EncodableValue("fontSize")] =
          flutter::EncodableValue(self->font_size_);
      self->EmitEvent("style", &payload);
      return 0;
    }
    case WM_CLOSE:
      self->EmitEvent("closed");
      ShowWindow(hwnd, SW_HIDE);
      return 0;
    case WM_NCDESTROY:
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
      return DefWindowProcW(hwnd, message, wparam, lparam);
    default:
      return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}
