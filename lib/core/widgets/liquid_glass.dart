// 文件说明：液态玻璃材质。
// 技术要点：BackdropFilter 采样背后的真实内容 → 低 alpha 染色 → 斜向薄膜高光
// → 0.8px 亮边。只有"一块胶囊/一条栏"用这层材质，整屏不再铺毛玻璃。

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/effect_policy.dart';
import 'glass_backdrop.dart';

/// 液态玻璃：真正透出背后内容的玻璃面。
///
/// 和之前的磨砂面板有三点区别，也正好是"看起来像塑料"的三个原因：
/// 1. 染色很淡（深色 0.22 / 浅色 0.46），背后的封面、文字要能透出来；
/// 2. 只留一道**薄膜高光**（左上白 → 右下透明），不是整块渐变底色；
/// 3. 边缘是一条 0.8px 的亮线，靠它收口，而不是靠实色底和投影。
///
/// 所以这个组件只应该用在"浮在内容上的一小块"——tab 胶囊、迷你播放条。
///
/// 注意：App 内只有全屏播放器允许背景模糊，这里默认走 [GlassQuality.minimal]
/// （不采样背后，只做透明混合 + 高光 + 细边）。因此染色浓度比"配模糊"的
/// 0.22 / 0.46 高——没有模糊垫底时，太淡会让胶囊上的字被背景吃掉。
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
    this.quality = GlassQuality.premium,
    this.backdrop = true,
    this.blurBehind = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final double saturation;

  /// 材质质量。调用方只描述场景，具体渲染后端由组件统一决定。
  final GlassQuality quality;

  /// 兼容旧调用点的显式开关；为 false 时等价于 [GlassQuality.minimal]。
  final bool backdrop;

  /// 是否允许实时采样背后做模糊。默认 false，只有全屏播放器才该打开。
  final bool blurBehind;

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
    // 有模糊垫底时染色可以很淡（0.22 / 0.46）；只剩透明度时同一档会让字
    // 糊在背景里，所以浓一档。
    final alpha =
        (blurBehind
            ? (isDark ? 0.22 : 0.46)
            : (isDark ? 0.58 : 0.74)) *
        opacity;
    final edge =
        borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.20 * opacity)
            : const Color(0xFF3C3C43).withValues(alpha: 0.14 * opacity));
    // 产品约定：只有全屏播放器允许模糊，其余界面只做透明混合。
    final requested = (backdrop && blurBehind) ? quality : GlassQuality.minimal;
    final resolved = resolveGlassQuality(context, requested: requested);

    return switch (resolved) {
      GlassQuality.off => _fallback(context, base: base, edge: edge),
      GlassQuality.minimal => _minimal(
        base: base,
        edge: edge,
        alpha: alpha,
        isDark: isDark,
      ),
      GlassQuality.standard => _backdrop(
        base: base,
        edge: edge,
        alpha: alpha,
        isDark: isDark,
        blur: blur.clamp(0, 12).toDouble(),
        saturation: 1.0,
      ),
      GlassQuality.premium => _backdrop(
        base: base,
        edge: edge,
        alpha: alpha,
        isDark: isDark,
        blur: blur,
        saturation: saturation,
      ),
    };
  }

  Widget _backdrop({
    required Color base,
    required Color edge,
    required double alpha,
    required bool isDark,
    required double blur,
    required double saturation,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: GlassBackdrop(
          sigma: blur,
          saturation: saturation,
          allowBlur: blurBehind,
          child: _layers(base: base, edge: edge, alpha: alpha, isDark: isDark),
        ),
      ),
    );
  }

  /// 滚动期使用的 Minimal 档：不读取背后纹理，只做一次普通透明混合，
  /// 再保留高光和边缘。因此视觉上仍是玻璃，但不会触发 BackdropFilter 的重采样。
  Widget _minimal({
    required Color base,
    required Color edge,
    required double alpha,
    required bool isDark,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: base.withValues(alpha: alpha),
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: _layers(
          base: Colors.transparent,
          edge: edge,
          alpha: 0,
          isDark: isDark,
        ),
      ),
    );
  }

  Widget _layers({
    required Color base,
    required Color edge,
    required double alpha,
    required bool isDark,
  }) {
    return Stack(
      children: [
        if (alpha > 0)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: base.withValues(alpha: alpha)),
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
    );
  }

  /// 简化特效 / 增强对比度 / 系统关掉动画：不做 backdrop 采样，退回一层接近
  /// 不透明的底色。判定见 [prefersFlatSurfaces]。
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
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: _layers(
          base: Colors.transparent,
          edge: edge,
          alpha: 0,
          isDark: AppColors.isDark(context),
        ),
      ),
    );
  }
}
