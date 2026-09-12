#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <flutter_windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// 首页内容实测高度 549（含上下内边距）+ 底部 chrome 154（导航栏 38 + 迷你播放器 78
// + 各处间隙）= 703，低于这个高度首页就要滚动，所以它是默认窗口高度的硬下限。
// （实测方式见 test/home_content_height_test.dart。）
constexpr int kHomeContentHeight = 704;
// 在内容下限之上再留出的呼吸余量。
constexpr int kBreathingRoom = 76;
// 桌面端默认高度 = 首页内容下限 + 呼吸余量。按「刚好装下首页且不局促」定，
// 而不是按屏幕高度的百分比——百分比在高分辨率屏上会开出一个几乎顶满整屏的窗口。
constexpr int kComfortableContentHeight = kHomeContentHeight + kBreathingRoom;
// 但小屏上不能顶满：最多占工作区高度的这个比例，其余留给桌面。
constexpr double kMaxWorkAreaFraction = 0.85;
// 屏幕实在放不下时的保底高度；再矮就交给首页自身滚动。
constexpr int kMinContentHeight = 560;
// 内容宽度下限（逻辑单位）。首页快捷功能卡片是「图标 + 标题/副标题 + 箭头」的
// 横向布局，宽度再窄副标题就会被省略号截断（最长副标题 8 个汉字，11pt 下约 88pt）。
constexpr int kMinContentWidth = 420;
// 窗口距屏幕上边缘的距离，以及底部至少留出的桌面高度，避免贴死任务栏。
constexpr int kWindowOrigin = 10;
constexpr int kBottomClearance = 20;
// Win32Window::Create 收的是窗口外框尺寸，而 Dart 侧拿到的是客户区
// （见 FlutterWindow::OnCreate 里的 GetClientArea）。WS_OVERLAPPEDWINDOW 的
// 标题栏与可调边框在逻辑单位下近似恒定，这里补回去，让上面的常数真正表示内容区。
constexpr int kNonClientWidth = 16;
constexpr int kNonClientHeight = 39;
// iPhone 17 竖屏比例：1206 x 2622 像素。只有在屏幕足够高时才会用到；
// 多数情况宽度下限先一步生效，窗口会比手机略宽一点（仍是竖屏）。
constexpr double kPortraitWidthPerHeight = 1206.0 / 2622.0;

// 宽度取 iPhone 17 的比例，但不低于 kMinContentWidth。
int ContentWidthFor(int content_height) {
  const int scaled_width =
      static_cast<int>(content_height * kPortraitWidthPerHeight);
  return scaled_width < kMinContentWidth ? kMinContentWidth : scaled_width;
}

// 把「想要的内容区高度」换算成 Create 需要的外框尺寸。Win32Window::Create 会把
// 这里返回的值乘上 DPI 缩放系数，所以用的是逻辑单位（Win32Window::Size 的字段是
// 无符号整数，转换一律显式写出——runner 带 /W4 /WX 编译）。
Win32Window::Size OuterSizeFor(int content_height) {
  return Win32Window::Size(
      static_cast<unsigned int>(ContentWidthFor(content_height) +
                                kNonClientWidth),
      static_cast<unsigned int>(content_height + kNonClientHeight));
}

Win32Window::Size DefaultWindowSize() {
  const POINT origin = {kWindowOrigin, kWindowOrigin};
  HMONITOR monitor = ::MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);

  MONITORINFO monitor_info{};
  monitor_info.cbSize = static_cast<DWORD>(sizeof(monitor_info));
  if (monitor == nullptr || !::GetMonitorInfoW(monitor, &monitor_info)) {
    return OuterSizeFor(kComfortableContentHeight);
  }

  const RECT work_area = monitor_info.rcWork;
  const double scale_factor = ::FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const int work_height =
      static_cast<int>((work_area.bottom - work_area.top) / scale_factor);

  // 外框高度 = 内容高度 + 非客户区，所以工作区里能容纳的内容高度要把上边距、
  // 底部留白和非客户区一并扣掉。
  const int max_content_height =
      work_height - kWindowOrigin - kBottomClearance - kNonClientHeight;

  // 三重约束取最小：舒适高度 / 工作区占比上限 / 实际能放下的高度。
  int content_height =
      static_cast<int>(work_height * kMaxWorkAreaFraction);
  if (content_height > kComfortableContentHeight) {
    content_height = kComfortableContentHeight;
  }
  if (content_height > max_content_height) {
    content_height = max_content_height;
  }
  if (content_height < kMinContentHeight) {
    content_height = kMinContentHeight;
  }

  return OuterSizeFor(content_height);
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
  Win32Window::Point origin(static_cast<unsigned int>(kWindowOrigin),
                            static_cast<unsigned int>(kWindowOrigin));
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
