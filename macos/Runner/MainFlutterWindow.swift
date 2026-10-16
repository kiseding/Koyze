import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // 首页内容高度以 test/home_content_height_test.dart 为准；底部 Dock 和悬浮播放器
  // 预留约 160px，低于这个高度首页就要滚动，
  // 所以它是默认窗口高度的硬下限。（实测方式见 test/home_content_height_test.dart。）
  private static let homeContentHeight: CGFloat = 782
  // 在内容下限之上再留出的呼吸余量。
  private static let breathingRoom: CGFloat = 76
  // 桌面端默认高度 = 首页内容下限 + 呼吸余量。按「刚好装下首页且不局促」定，
  // 而不是按屏幕高度的百分比——百分比在高分辨率屏上会开出一个几乎顶满整屏的窗口。
  private static let comfortableContentHeight: CGFloat =
    homeContentHeight + breathingRoom
  // 但小屏上不能顶满：最多占屏幕可用高度的这个比例，其余留给桌面。
  private static let maxVisibleFrameFraction: CGFloat = 0.85
  // 屏幕实在放不下时的保底高度；再矮就交给首页自身滚动。
  private static let minContentHeight: CGFloat = 560
  // 宽度下限（逻辑点），防止极小工作区把快捷功能卡片压得过窄。
  private static let minLandscapeWidth: CGFloat = 420
  // 标题栏 + 居中后上下留出的空隙。
  private static let verticalChrome: CGFloat = 80
  // PC 端默认窗口使用 4:3 横屏比例。
  private static let landscapeWidthPerHeight: CGFloat = 4.0 / 3.0

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.applyLandscapeDefaultSize()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 默认高度按首页内容定（见上方常数），窗口放不下时再按屏幕可用高度收缩。
  /// setContentSize 收的就是内容区尺寸，所以这里不需要补偿标题栏。
  private func applyLandscapeDefaultSize() {
    var height = MainFlutterWindow.comfortableContentHeight

    if let visibleFrame = (self.screen ?? NSScreen.main)?.visibleFrame {
      // 三重约束取最小：舒适高度 / 屏幕可用高度占比上限 / 实际能放下的高度。
      let proportional =
        (visibleFrame.height * MainFlutterWindow.maxVisibleFrameFraction).rounded()
      let maxHeight = visibleFrame.height - MainFlutterWindow.verticalChrome
      height = min(height, proportional)
      height = min(height, maxHeight)
      height = max(height, MainFlutterWindow.minContentHeight)
    }

    let scaledWidth =
      (height * MainFlutterWindow.landscapeWidthPerHeight).rounded()
    let width = max(scaledWidth, MainFlutterWindow.minLandscapeWidth)
    self.setContentSize(NSSize(width: width, height: height))
    self.center()
  }
}
