import 'dart:ui';

import 'package:flutter/material.dart';

/// 顶栏背景：整栏磨砂玻璃，无底部渐变透明。
/// 配合 `AppBar.flexibleSpace` 或榜单 tab 悬浮 header 使用。
/// 注意：`AppBar.flexibleSpace` 收到的约束是 loose 的，无 child 时必须撑满，
/// 否则装饰会被压缩成 0×0 而完全不可见。
class GradientAppBarBackground extends StatelessWidget {
  const GradientAppBarBackground({
    super.key,
    required this.background,
    this.child,
  });

  /// 磨砂上叠的底色。
  final Color background;

  /// 可选子内容（如自定义标题栏），置于磨砂之上。
  final Widget? child;

  static const double _tintAlpha = 0.62;

  @override
  Widget build(BuildContext context) {
    final frost = ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: ColoredBox(
          color: background.withValues(alpha: _tintAlpha),
          child: child,
        ),
      ),
    );
    if (child != null) {
      return frost;
    }
    // 无 child（如 AppBar.flexibleSpace）时撑满可用区域，
    // 避免 loose 约束下被压缩成 0×0 导致磨砂不可见。
    return SizedBox.expand(child: frost);
  }
}

/// 底栏背景：栏顶部 13% 透明度从 100% 渐变到 3%，下方 87% 从 3% 渐变到 0%。
/// 包裹分页栏等底部控件使用。
class GradientBottomBarBackground extends StatelessWidget {
  const GradientBottomBarBackground({
    super.key,
    required this.background,
    required this.child,
    this.minAlpha = 0.0,
  });

  /// 栏顶部露出的背景色。
  final Color background;

  /// 渐变最透处的透明度（0~1）。
  final double minAlpha;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            background.withValues(alpha: minAlpha),
            background.withValues(alpha: 0.97),
            background,
          ],
          // 顶部 13%：透明度 100%→3%，下方 87%：3%→0%。
          stops: const [0.0, 0.13, 1.0],
        ),
      ),
      child: child,
    );
  }
}
