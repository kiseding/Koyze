import 'package:flutter/material.dart';

import '../performance/low_memory.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/glass_config.dart';

/// 液态玻璃：单色低 alpha 的模糊面，靠模糊后的底色和 0.8px 边缘定义形状。
///
/// 和 origo-x 的 chrome 一致——**不做斜向渐变**。之前那层从左上到右下的白色
/// 渐变会把面板画成一块带反光的塑料；现在整面只有一层均匀染色，明暗全部来自
/// 背后被模糊的内容，只有最上沿留一道很薄的折光。
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.blur = 26,
    this.saturation = 1.45,
    this.opacity = 1,
    this.boxShadow,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final double saturation;

  /// 0–1 倍率：淡出、收起时整体减淡。
  final double opacity;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final tint = AppGlass.tintBase(context);
    final alpha =
        GlassEffectConfig.chromeOpacityFor(
          Theme.of(context).colorScheme.brightness,
        ) *
        opacity;
    final rim = Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.18 * opacity)
          : const Color(0xFF3C3C43).withValues(alpha: 0.12 * opacity),
      width: 0.8,
    );

    if (LowMemory.active) {
      return _opaqueFallback(context, tint: tint, rim: rim);
    }

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: boxShadow),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: AppGlass.liquidFilter(blur: blur, saturation: saturation),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: alpha),
                    borderRadius: borderRadius,
                  ),
                ),
              ),
              child,
              // 上沿一道极薄的折光：只是让玻璃有个上边，不是整块高光。
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.04, 0.5, 1],
                        colors: [
                          Colors.white.withValues(
                            alpha: (isDark ? 0.08 : 0.14) * opacity,
                          ),
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(
                            alpha: (isDark ? 0.02 : 0.04) * opacity,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: rim,
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

  /// 低内存/低端机：不做 backdrop 采样，退回一层半透明底色。
  Widget _opaqueFallback(
    BuildContext context, {
    required Color tint,
    required Border rim,
  }) {
    final base = Color.alphaBlend(
      tint.withValues(alpha: AppColors.isDark(context) ? 0.92 : 0.88),
      AppColors.scaffold(context),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: borderRadius,
        border: rim,
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
