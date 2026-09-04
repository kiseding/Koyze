import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared glass tokens for floating overlays.
abstract final class AppGlass {
  static const double blur = 24;

  static Color fill(BuildContext context, {double? alpha}) {
    final isDark = AppColors.isDark(context);
    final resolved = alpha ?? (isDark ? 0.78 : 0.86);
    return (isDark ? AppColors.surfaceDark : Colors.white).withValues(
      alpha: resolved,
    );
  }
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.color,
    this.border,
    this.blur = AppGlass.blur,
    this.boxShadow,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Border? border;
  final double blur;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    final glass = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? AppGlass.fill(context),
            borderRadius: radius,
            border:
                border ??
                Border.all(
                  color: AppColors.isDark(context)
                      ? const Color(0x24FFFFFF)
                      : const Color(0x18000000),
                  width: 0.5,
                ),
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
    if (boxShadow == null || boxShadow!.isEmpty) return glass;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: boxShadow),
      child: glass,
    );
  }
}
