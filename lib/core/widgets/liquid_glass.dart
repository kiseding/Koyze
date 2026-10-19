// 文件说明：液态玻璃材质。
// 技术要点：BackdropFilter 采样背后的真实内容 → 低 alpha 染色 → 斜向薄膜高光
// → 0.8px 亮边。只有"一块胶囊/一条栏"用这层材质，整屏不再铺毛玻璃。

import 'dart:ui';

import 'package:flutter/material.dart';

import '../performance/low_memory.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// 液态玻璃：真正透出背后内容的玻璃面。
///
/// 和之前的磨砂面板有三点区别，也正好是"看起来像塑料"的三个原因：
/// 1. 染色很淡（深色 0.22 / 浅色 0.46），背后的封面、文字要能透出来；
/// 2. 只留一道**薄膜高光**（左上白 → 右下透明），不是整块渐变底色；
/// 3. 边缘是一条 0.8px 的亮线，靠它收口，而不是靠实色底和投影。
///
/// 所以这个组件只应该用在"浮在内容上的一小块"——tab 胶囊、迷你播放条。
/// 整条栏铺满屏幕宽度时把 alpha 留在 0.2 以下，否则又变成一张毛玻璃板。
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.blur = 24,
    this.saturation = 1.55,
    this.opacity = 1,
    this.tint,
    this.boxShadow,
    this.sheen = true,
    this.borderColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final double saturation;

  /// 0–1 倍率：淡出、收起时整体减淡。
  final double opacity;

  /// 覆盖染色基色；默认取中性 surface。
  final Color? tint;
  final List<BoxShadow>? boxShadow;

  /// 薄膜高光。极小的控件可以关掉，避免高光盖住图标。
  final bool sheen;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final base = tint ?? AppGlass.tintBase(context);
    // 比旧的 chrome 档（0.30 / 0.60）再淡一档：玻璃要能看到背后的东西。
    final alpha = (isDark ? 0.22 : 0.46) * opacity;
    final edge =
        borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.20 * opacity)
            : const Color(0xFF3C3C43).withValues(alpha: 0.14 * opacity));

    if (LowMemory.active) {
      return _fallback(context, base: base, edge: edge);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: AppGlass.liquidFilter(
            blur: blur,
            saturation: saturation,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: base.withValues(alpha: alpha),
                  ),
                ),
              ),
              if (sheen)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0, 0.42, 1],
                          colors: [
                            Colors.white.withValues(
                              alpha: (isDark ? 0.14 : 0.42) * opacity,
                            ),
                            Colors.white.withValues(
                              alpha: (isDark ? 0.03 : 0.08) * opacity,
                            ),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              child,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(color: edge, width: 0.8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 低内存/低端机：不做 backdrop 采样，退回一层接近不透明的底色。
  Widget _fallback(
    BuildContext context, {
    required Color base,
    required Color edge,
  }) {
    final opaque = Color.alphaBlend(
      base.withValues(alpha: AppColors.isDark(context) ? 0.90 : 0.86),
      AppColors.scaffold(context),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: opaque,
        borderRadius: borderRadius,
        border: Border.all(color: edge, width: 0.8),
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
