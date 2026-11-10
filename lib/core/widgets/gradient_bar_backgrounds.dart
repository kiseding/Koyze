import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'origo_chrome.dart';

/// 顶栏（状态栏 + toolbar）占的高度。
///
/// 页面的 `extendBodyBehindAppBar` 一打开，body 就从屏幕最顶开始画；滚动内容
/// 必须自己让出这一段，否则第一个卡片会钻进标题底下。统一走这个函数，避免
/// 各页各写一份 `kToolbarHeight + padding.top`（漏掉 padding 的那几页在刘海屏
/// 上卡片是压着状态栏的）。
double koyzeAppBarExtent(BuildContext context) =>
    MediaQuery.paddingOf(context).top + kToolbarHeight;

/// 顶栏下方内容的默认上内边距。
///
/// [extra] 是各页原本自己的上边距（比如 8 / 20）。
EdgeInsets koyzeAppBarContentPadding(
  BuildContext context, {
  double extra = 8,
  double horizontal = 16,
  double bottom = 32,
}) {
  return EdgeInsets.fromLTRB(
    horizontal,
    koyzeAppBarExtent(context) + extra,
    horizontal,
    bottom,
  );
}

/// 配合 `extendBodyBehindAppBar: true` 的 body 包装。
///
/// 为什么要让 body 从栏下穿过：顶栏是半透明的，背后若是纯色页面底，把
/// 「界面不透明度」调低只会让栏自己变淡，看不到任何内容——那不叫玻璃。
/// 让滚动视口从屏幕最顶开始、只把内容的起点下移一个栏高，滚动时列表才会
/// 从栏底下经过，透明度才有东西可透。
///
/// 只用于 body 是 [Column]、非滚动容器的页面；滚动列表请直接用它自己的
/// `padding: koyzeAppBarContentPadding(context)`，那样滚动视口才是全屏的。
class KoyzeAppBarBody extends StatelessWidget {
  const KoyzeAppBarBody({super.key, required this.child, this.extra = 0});

  final Widget child;
  final double extra;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: koyzeAppBarExtent(context) + extra),
      child: child,
    );
  }
}

/// Top chrome backdrop: frost tapers out toward the list instead of ending on
/// a hard edge. Pair with [GlassSurface] only when an opaque panel is wanted.
/// 注意：`AppBar.flexibleSpace` 收到的约束是 loose 的，无 child 时必须撑满，
/// 否则装饰会被压缩成 0×0 而完全不可见。
class GradientAppBarBackground extends StatelessWidget {
  const GradientAppBarBackground({
    super.key,
    required this.background,
    this.child,
    this.blur,
    this.vivid = true,
  });

  /// 保留参数以兼容现有调用；实际 tint 由玻璃底色决定。
  final Color background;

  /// 可选子内容（如自定义标题栏），置于磨砂之上。
  final Widget? child;

  /// 覆盖磨砂半径。列表从栏下穿过时用较小值，避免每帧全强度模糊。
  final double? blur;

  /// 保留参数以兼容现有调用；渐变磨砂本身就是多段淡出。
  final bool vivid;

  @override
  Widget build(BuildContext context) {
    final frost = GradientFrost(
      sigma: blur ?? 16,
      child: child ?? const SizedBox.expand(),
    );
    if (child != null) return frost;
    return SizedBox.expand(child: frost);
  }
}

/// 底栏背景：iOS tab bar 式磨砂，越靠近列表越糊，顶缘淡出。
class GradientBottomBarBackground extends StatelessWidget {
  const GradientBottomBarBackground({
    super.key,
    required this.background,
    required this.child,
    this.minAlpha = 0.0,
  });

  /// 保留参数以兼容现有调用；实际 tint 由 [AppGlassStyle.bar] 决定。
  final Color background;

  /// 保留参数以兼容现有调用。
  final double minAlpha;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      style: AppGlassStyle.bar,
      borderRadius: BorderRadius.zero,
      border: const Border(),
      fade: AppGlassFade.up,
      child: child,
    );
  }
}
