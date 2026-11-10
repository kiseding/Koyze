import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 状态栏 / 导航栏图标配色。
///
/// 为什么不靠 `AppBarTheme.systemOverlayStyle`：
///
/// Flutter 不是「设一个全局样式就一直生效」，而是每帧在图层树里按状态栏
/// 中心点（`(宽/2, padding.top/2)`）找最近的 `AnnotatedRegion<SystemUiOverlayStyle>`。
/// 只有 `AppBar` 会顺手插一个这样的 region。根页面（首页、榜单、歌单、设置）
/// 没有 `AppBar`，顶部一条里就什么都没有，`RenderView._updateSystemChrome`
/// 直接 return、不调 `SystemChrome.setSystemUIOverlayStyle`——引擎于是停在
/// 它自己的默认值上，而那个默认值给的是**亮色图标**。亮色主题的白底配上
/// 白色图标，就是「状态栏文字图标全看不见」。
///
/// 所以这里在整棵应用的最外层包一个 `AnnotatedRegion`，让任何页面（含没有
/// 标题栏的根页）都有一个兜底值；`AppBar` 自己的 region 在它上面，仍然优先。
class KoyzeSystemBars extends StatelessWidget {
  const KoyzeSystemBars({super.key, required this.child});

  final Widget child;

  /// 按当前主题亮度给出状态栏样式。
  ///
  /// - `statusBarIconBrightness` 是 Android 用的：`dark` = 深色图标。
  /// - `statusBarBrightness` 是 iOS 用的，语义**相反**：`light` = 深色图标
  ///   （表示「背景是亮的」）。
  ///
  /// 两个都要给，只给一个会在另一个平台上失效。
  static SystemUiOverlayStyle styleFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      // 导航栏跟着走，否则浅色主题下三键导航也会是白图标压白底。
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      // 透明状态下 Android 10+ 会自动垫一层半透明遮罩保证对比度，那层
      // 遮罩在浅色页面上是一道灰带，很难看；关掉它，对比度由我们自己
      // 用图标颜色保证。
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 用 Theme.of 而不是 MediaQuery.platformBrightness：应用内的主题
    // 可以手动指定深浅（themeMode），和系统亮度不一定一致。页面底色是
    // 由应用主题决定的，图标就得跟着应用主题走。
    final brightness = Theme.of(context).brightness;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: styleFor(brightness),
      child: child,
    );
  }
}

/// 把一段内容标记成「深色背景」，其中的系统栏用亮色图标。
///
/// 全屏播放页是深色沉浸式的，它的背景和主题亮度无关——浅色主题下打开
/// 播放页，封面背景压暗后依然是深色，那里就该用白色图标。局部套一层
/// 这个，比让页面自己算一遍 overlay style 更不容易漏。
class DarkSystemBars extends StatelessWidget {
  const DarkSystemBars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: KoyzeSystemBars.styleFor(Brightness.dark),
      child: child,
    );
  }
}
