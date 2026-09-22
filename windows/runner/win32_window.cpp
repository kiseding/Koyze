#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <windowsx.h>

#include <unordered_map>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_NCRENDERING_POLICY
#define DWMWA_NCRENDERING_POLICY 2
#endif
#ifndef DWMNCRP_DISABLED
#define DWMNCRP_DISABLED 1
#endif
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_COLOR_NONE
#define DWMWA_COLOR_NONE 0xFFFFFFFE
#endif
// 未公开消息：DWM 用它们绘制标题按钮悬停时的灰色高亮带。
#ifndef WM_NCUAHDRAWCAPTION
#define WM_NCUAHDRAWCAPTION 0x00AE
#endif
#ifndef WM_NCUAHDRAWFRAME
#define WM_NCUAHDRAWFRAME 0x00AF
#endif

constexpr DWORD kDwmCornerRound = 2;
constexpr int kCornerRadiusDip = 24;
constexpr int kResizeBorderDip = 6;

struct ChildHook {
  WNDPROC original = nullptr;
  HWND owner = nullptr;
};

std::unordered_map<HWND, ChildHook> g_child_hooks;

void EnableImmersiveFrame(HWND window) {
  // 负边距会把整窗变成玻璃。鼠标停在右上角时，DWM 仍会在系统按钮的位置
  // 涂一条灰色悬停带。边距清零，并关掉非客户区绘制。
  const MARGINS margins = {0, 0, 0, 0};
  DwmExtendFrameIntoClientArea(window, &margins);
  const DWORD nc_policy = DWMNCRP_DISABLED;
  DwmSetWindowAttribute(window, DWMWA_NCRENDERING_POLICY, &nc_policy,
                        sizeof(nc_policy));
  const COLORREF border = DWMWA_COLOR_NONE;
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border, sizeof(border));
  const COLORREF caption = DWMWA_COLOR_NONE;
  DwmSetWindowAttribute(window, DWMWA_CAPTION_COLOR, &caption, sizeof(caption));
  const DWORD corner = kDwmCornerRound;
  DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE, &corner,
                        sizeof(corner));
}

// 去掉 WS_CAPTION 后，DWM 的圆角偏好经常不生效。用区域把四角裁圆。
// 最大化时清掉区域，让窗口贴齐工作区。
void ApplyRoundedCorners(HWND window) {
  if (!window) {
    return;
  }
  if (IsZoomed(window)) {
    SetWindowRgn(window, nullptr, TRUE);
    return;
  }
  RECT rect{};
  if (!GetWindowRect(window, &rect)) {
    return;
  }
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  const int diameter = MulDiv(kCornerRadiusDip * 2, GetDpiForWindow(window), 96);
  HRGN region =
      CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter, diameter);
  if (region) {
    SetWindowRgn(window, region, TRUE);
  }
}

LRESULT BorderHitTest(HWND hwnd, LPARAM lparam) {
  if (!hwnd || IsZoomed(hwnd)) {
    return HTCLIENT;
  }
  POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  RECT window_rect{};
  if (!GetWindowRect(hwnd, &window_rect)) {
    return HTCLIENT;
  }
  const int dpi = GetDpiForWindow(hwnd);
  // 右上角是自绘按钮，并且要比 24px 圆角再往里让一截。
  // 这里如果返回 HTTOP，DWM 会画出系统按钮的灰色悬停带。
  const int button_band = MulDiv(160, dpi, 96);
  const int caption_height = MulDiv(40, dpi, 96);
  if (pt.x >= window_rect.right - button_band &&
      pt.y < window_rect.top + caption_height) {
    return HTCLIENT;
  }
  const int border = MulDiv(kResizeBorderDip, dpi, 96);
  const bool left = pt.x < window_rect.left + border;
  const bool right = pt.x >= window_rect.right - border;
  const bool top = pt.y < window_rect.top + border;
  const bool bottom = pt.y >= window_rect.bottom - border;
  if (top && left) {
    return HTTOPLEFT;
  }
  if (top && right) {
    return HTTOPRIGHT;
  }
  if (bottom && left) {
    return HTBOTTOMLEFT;
  }
  if (bottom && right) {
    return HTBOTTOMRIGHT;
  }
  if (left) {
    return HTLEFT;
  }
  if (right) {
    return HTRIGHT;
  }
  if (top) {
    return HTTOP;
  }
  if (bottom) {
    return HTBOTTOM;
  }
  return HTCLIENT;
}

LRESULT CALLBACK ChildResizeProc(HWND hwnd,
                                 UINT message,
                                 WPARAM wparam,
                                 LPARAM lparam) {
  const auto found = g_child_hooks.find(hwnd);
  if (found != g_child_hooks.end() && message == WM_NCHITTEST &&
      BorderHitTest(found->second.owner, lparam) != HTCLIENT) {
    return HTTRANSPARENT;
  }
  if (found != g_child_hooks.end() && found->second.original) {
    return CallWindowProcW(found->second.original, hwnd, message, wparam,
                           lparam);
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

// WS_OVERLAPPEDWINDOW 自带 WS_CAPTION。只改客户区时，DWM 仍会在顶上画出
// 系统标题文字和最小化/最大化/关闭。这里拆掉标题栏，保留可缩放边框。
void RemoveNativeCaption(HWND window) {
  LONG style = GetWindowLong(window, GWL_STYLE);
  style &= ~WS_CAPTION;
  style |= WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU;
  SetWindowLong(window, GWL_STYLE, style);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  ApplyRoundedCorners(window);
}

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr UINT kTrayIconMessage = WM_APP + 1;
constexpr UINT kExitApplicationMessage = WM_APP + 2;
constexpr UINT kTrayOpenCommand = 1;
constexpr UINT kTrayExitCommand = 2;
constexpr const wchar_t kRestoreInstanceMessageName[] =
    L"Koyze.RestoreInstance";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
  taskbar_created_message_ = RegisterWindowMessage(L"TaskbarCreated");
  restore_instance_message_ =
      RegisterWindowMessageW(kRestoreInstanceMessageName);
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  if (message == taskbar_created_message_ && hidden_to_tray_) {
    tray_icon_added_ = false;
    AddTrayIcon();
    return 0;
  }
  if (restore_instance_message_ != 0 && message == restore_instance_message_) {
    RestoreFromTray();
    return 0;
  }

  switch (message) {
    case WM_CLOSE: {
      if (exiting_) {
        DestroyWindow(hwnd);
        return 0;
      }
      OnCloseRequested();
      return 0;
    }

    case kTrayIconMessage:
      if (LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        RestoreFromTray();
      } else if (LOWORD(lparam) == WM_RBUTTONUP ||
                 LOWORD(lparam) == WM_CONTEXTMENU) {
        ShowTrayMenu();
      }
      return 0;

    case kExitApplicationMessage:
      exiting_ = true;
      DestroyWindow(hwnd);
      return 0;

    case WM_DESTROY:
      RemoveTrayIcon();
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      ApplyRoundedCorners(hwnd);
      return 0;
    }

    case WM_NCPAINT:
      return 0;

    case WM_NCUAHDRAWCAPTION:
    case WM_NCUAHDRAWFRAME:
      return 0;

    case WM_NCHITTEST:
      return BorderHitTest(hwnd, lparam);

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_NCACTIVATE:
      // -1 让系统不要在激活时把原生标题栏画回来。
      return DefWindowProc(hwnd, message, wparam, -1);

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;

    case WM_NCCALCSIZE: {
      if (wparam != TRUE) {
        break;
      }
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      if (IsZoomed(hwnd)) {
        // 最大化时客户区必须停在工作区里，否则会盖住任务栏。
        MONITORINFO monitor_info{};
        monitor_info.cbSize = sizeof(monitor_info);
        const HMONITOR monitor =
            MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
        if (GetMonitorInfoW(monitor, &monitor_info)) {
          params->rgrc[0] = monitor_info.rcWork;
        }
        return 0;
      }
      // 盖住 Windows 在顶边悬停时画的一像素高亮。
      params->rgrc[0].top -= 1;
      return 0;
    }
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  RemoveTrayIcon();
  OnDestroy();

  if (child_content_) {
    const auto found = g_child_hooks.find(child_content_);
    if (found != g_child_hooks.end()) {
      SetWindowLongPtrW(child_content_, GWLP_WNDPROC,
                        reinterpret_cast<LONG_PTR>(found->second.original));
      g_child_hooks.erase(found);
    }
    child_content_ = nullptr;
  }

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  if (g_child_hooks.find(content) == g_child_hooks.end()) {
    ChildHook hook;
    hook.owner = window_handle_;
    hook.original = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
        content, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(ChildResizeProc)));
    g_child_hooks.emplace(content, hook);
  }
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::OnCloseRequested() {
  ExitApplication();
}

bool Win32Window::HideToTray() {
  if (!AddTrayIcon()) {
    return false;
  }
  hidden_to_tray_ = true;
  ShowWindow(window_handle_, SW_HIDE);
  return true;
}

void Win32Window::ExitApplication() {
  if (window_handle_) {
    PostMessageW(window_handle_, kExitApplicationMessage, 0, 0);
  }
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
  EnableImmersiveFrame(window);
  RemoveNativeCaption(window);
}

bool Win32Window::AddTrayIcon() {
  if (tray_icon_added_ || !window_handle_) {
    return tray_icon_added_;
  }

  tray_icon_ = {};
  tray_icon_.cbSize = sizeof(tray_icon_);
  tray_icon_.hWnd = window_handle_;
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayIconMessage;
  tray_icon_.hIcon = LoadIcon(GetModuleHandle(nullptr),
                              MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"Koyze");
  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_) == TRUE;
  if (tray_icon_added_) {
    tray_icon_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_);
  }
  return tray_icon_added_;
}

void Win32Window::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  tray_icon_added_ = false;
}

void Win32Window::RestoreFromTray() {
  if (!window_handle_) {
    return;
  }
  hidden_to_tray_ = false;
  RemoveTrayIcon();
  ShowWindow(window_handle_, SW_RESTORE);
  SetForegroundWindow(window_handle_);
}

void Win32Window::ShowTrayMenu() {
  if (!window_handle_) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kTrayOpenCommand, L"打开 Koyze");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExitCommand, L"退出");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(window_handle_);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x,
      cursor.y, 0, window_handle_, nullptr);
  DestroyMenu(menu);

  if (command == kTrayOpenCommand) {
    RestoreFromTray();
  } else if (command == kTrayExitCommand) {
    ExitApplication();
  }
}
