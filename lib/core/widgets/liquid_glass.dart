import 'package:flutter/material.dart';

import '../performance/low_memory.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// 液态玻璃：几乎不上色的模糊面，只靠边缘反光定义形状。
///
/// 和别处的磨砂卡片相反，它不是用来遮住底下的内容，而是**故意让底下透出来**：
/// 页面在它后面继续绘制，模糊把内容化成柔和的色块，顶部那道亮面和 0.9px 的
/// 边缘线负责把胶囊的轮廓勾出来。透明度一旦回到卡片那种档位，它立刻又变回
/// 一条实心横条——所以这里的 alpha 压得很低。
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.blur = 28,
    this.saturation = 1.7,
    this.opacity = 1,
    this.boxShadow,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final double saturation;

  /// 0–1 倍率：淡出、收起时整体减淡，避免逐层改多少透明度。
  final double opacity;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final tint = isDark ? const Color(0xFF2C2C30) : Colors.white;
    final lead = (isDark ? 0.34 : 0.32) * opacity;
    final trail = (isDark ? 0.16 : 0.16) * opacity;
    final rim = Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.22 * opacity)
          : const Color(0xFF3C3C43).withValues(alpha: 0.13 * opacity),
      width: 0.9,
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
                    borderRadius: borderRadius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tint.withValues(alpha: lead),
                        tint.withValues(alpha: trail),
                      ],
                    ),
                  ),
                ),
              ),
              child,
              // 光线从玻璃上沿折进来的一道薄亮面，下沿只留一点点回光。
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.34, 0.74, 1],
                        colors: [
                          Colors.white.withValues(
                            alpha: (isDark ? 0.20 : 0.34) * opacity,
                          ),
                          Colors.white.withValues(alpha: 0.02 * opacity),
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(
                            alpha: (isDark ? 0.04 : 0.09) * opacity,
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
      tint.withValues(alpha: AppColors.isDark(context) ? 0.90 : 0.86),
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
