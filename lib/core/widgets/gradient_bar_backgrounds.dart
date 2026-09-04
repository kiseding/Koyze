import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 顶栏背景：iOS 导航栏式磨砂，越靠近列表越糊，底缘淡出。
/// 配合 `AppBar.flexibleSpace` 或榜单 tab 悬浮 header 使用。
/// 注意：`AppBar.flexibleSpace` 收到的约束是 loose 的，无 child 时必须撑满，
/// 否则装饰会被压缩成 0×0 而完全不可见。
class GradientAppBarBackground extends StatelessWidget {
  const GradientAppBarBackground({
    super.key,
    required this.background,
    this.child,
  });

  /// 保留参数以兼容现有调用；实际 tint 由 [AppGlassStyle.bar] 决定。
  final Color background;

  /// 可选子内容（如自定义标题栏），置于磨砂之上。
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final frost = GlassSurface(
      style: AppGlassStyle.bar,
      fade: AppGlassFade.down,
      borderRadius: BorderRadius.zero,
      border: const Border(),
      child: child ?? const SizedBox.expand(),
    );
    if (child != null) {
      return frost;
    }
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
      fade: AppGlassFade.up,
      borderRadius: BorderRadius.zero,
      border: const Border(),
      child: child,
    );
  }
}
