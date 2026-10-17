import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'origo_chrome.dart';

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
