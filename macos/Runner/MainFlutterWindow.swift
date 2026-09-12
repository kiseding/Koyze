import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // 首页内容实测高度 549（含上下内边距）+ 底部 chrome 154（导航栏 38 + 迷你播放器 78
  // + 各处间隙）= 703，低于这个高度首页就要滚动，所以它是默认窗口高度的硬下限。
  // （实测方式见 test/home_content_height_test.dart。）
  private static let homeContentHeight: CGFloat = 704
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
  // 内容宽度下限（逻辑点）。首页快捷功能卡片是「图标 + 标题/副标题 + 箭头」的
  // 横向布局，宽度再窄副标题就会被省略号截断（最长副标题 8 个汉字，11pt 下约 88pt）。
  private static let minContentWidth: CGFloat = 420
  // 标题栏 + 居中后上下留出的空隙。
  private static let verticalChrome: CGFloat = 80
  // iPhone 17 竖屏比例：1206 x 2622 像素。只有在屏幕足够高时才会用到；
  // 多数情况宽度下限先一步生效，窗口会比手机略宽一点（仍是竖屏）。
  private static let portraitWidthPerHeight: CGFloat = 1206.0 / 2622.0

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.applyPortraitDefaultSize()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 默认高度按首页内容定（见上方常数），窗口放不下时再按屏幕可用高度收缩。
  /// setContentSize 收的就是内容区尺寸，所以这里不需要补偿标题栏。
  private func applyPortraitDefaultSize() {
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

    let scaledWidth = (height * MainFlutterWindow.portraitWidthPerHeight).rounded()
    let width = max(scaledWidth, MainFlutterWindow.minContentWidth)
    self.setContentSize(NSSize(width: width, height: height))
    self.center()
  }
}
