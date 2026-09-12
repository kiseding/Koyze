import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // iPhone 17 竖屏比例：1206 x 2622 像素。
  private static let portraitWidthPerHeight: CGFloat = 1206.0 / 2622.0
  // 窗口高度的下限与上限（逻辑点）。上限避免在大屏上开出一个过大的窗口，
  // 下限避免在高缩放比的小屏上把界面压得过窄。
  private static let minContentHeight: CGFloat = 640
  private static let maxContentHeight: CGFloat = 960
  // 内容宽度的下限（逻辑点）。首页快捷功能卡片是「图标 + 标题/副标题 + 箭头」的
  // 横向布局，宽度再窄副标题就会被省略号截断（最长副标题 8 个汉字，11pt 下约 88pt）。
  private static let minContentWidth: CGFloat = 420
  // 取不到屏幕信息时的退路，同样是 iPhone 17 的比例。
  private static let fallbackContentHeight: CGFloat = 900

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.applyPortraitDefaultSize()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 默认按手机竖屏比例开窗：高度取屏幕可用高度的 90%（并夹在上下限之间），
  /// 宽度按 iPhone 17 的比例换算。屏幕高度受限时宽度会触到下限，
  /// 此时窗口会比手机略宽（仍是竖屏），换取界面文字完整显示。
  private func applyPortraitDefaultSize() {
    var height = MainFlutterWindow.fallbackContentHeight

    if let visibleFrame = (self.screen ?? NSScreen.main)?.visibleFrame {
      height = min(
        max((visibleFrame.height * 0.9).rounded(), MainFlutterWindow.minContentHeight),
        MainFlutterWindow.maxContentHeight
      )
    }

    let scaledWidth = (height * MainFlutterWindow.portraitWidthPerHeight).rounded()
    let width = max(scaledWidth, MainFlutterWindow.minContentWidth)
    self.setContentSize(NSSize(width: width, height: height))
    self.center()
  }
}
