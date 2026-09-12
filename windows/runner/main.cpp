#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <flutter_windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// iPhone 17 竖屏比例：1206 x 2622 像素。
constexpr double kPortraitWidthPerHeight = 1206.0 / 2622.0;
// 窗口高度的下限与上限（逻辑单位）。上限避免在大屏上开出一个过大的窗口，
// 下限避免在高缩放比的小屏上把界面压得过窄。
constexpr int kMinWindowHeight = 640;
constexpr int kMaxWindowHeight = 960;
// 内容宽度的下限（逻辑单位）。首页快捷功能卡片是「图标 + 标题/副标题 + 箭头」的
// 横向布局，宽度再窄副标题就会被省略号截断（最长副标题 8 个汉字，11pt 下约 88pt）。
constexpr int kMinWindowWidth = 420;
// 取不到显示器信息时的退路，同样是 iPhone 17 的比例。
constexpr int kFallbackWindowHeight = 900;

// 宽度取 iPhone 17 的比例，但不低于 kMinWindowWidth。
int PortraitWidthFor(int height) {
  const int scaled_width = static_cast<int>(height * kPortraitWidthPerHeight);
  return scaled_width < kMinWindowWidth ? kMinWindowWidth : scaled_width;
}

// 默认按手机竖屏比例开窗：高度取显示器工作区高度的 90%（并夹在上下限之间），
// 宽度按 iPhone 17 的比例换算。Win32Window::Create 会把这里返回的值乘上 DPI
// 缩放系数，所以这里用的是逻辑单位（Win32Window::Size 的字段是无符号整数，
// 转换一律显式写出，runner 是带 /W4 /WX 编译的）。
Win32Window::Size DefaultWindowSize() {
  const POINT origin = {10, 10};
  HMONITOR monitor = ::MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);

  MONITORINFO monitor_info{};
  monitor_info.cbSize = static_cast<DWORD>(sizeof(monitor_info));
  if (monitor == nullptr || !::GetMonitorInfoW(monitor, &monitor_info)) {
    return Win32Window::Size(
        static_cast<unsigned int>(PortraitWidthFor(kFallbackWindowHeight)),
        static_cast<unsigned int>(kFallbackWindowHeight));
  }

  const RECT work_area = monitor_info.rcWork;
  const double scale_factor = ::FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const int work_height =
      static_cast<int>((work_area.bottom - work_area.top) / scale_factor);

  int height = static_cast<int>(work_height * 0.9);
  if (height < kMinWindowHeight) {
    height = kMinWindowHeight;
  } else if (height > kMaxWindowHeight) {
    height = kMaxWindowHeight;
  }

  return Win32Window::Size(static_cast<unsigned int>(PortraitWidthFor(height)),
                           static_cast<unsigned int>(height));
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE instance_mutex =
      CreateMutexW(nullptr, FALSE, L"Local\\KoyzeSingleInstance");
  if (instance_mutex && GetLastError() == ERROR_ALREADY_EXISTS) {
    const UINT restore_message =
        RegisterWindowMessageW(L"Koyze.RestoreInstance");
    PostMessageW(HWND_BROADCAST, restore_message, 0, 0);
    CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size = DefaultWindowSize();
  if (!window.Create(L"Koyze", origin, size)) {
    if (instance_mutex) {
      CloseHandle(instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex) {
    CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
