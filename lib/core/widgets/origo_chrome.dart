import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Shared Origo-style surface: a quiet highlight, clear edge and floating
/// shadow around the existing frosted material.
class OrigoChromeSurface extends StatelessWidget {
  const OrigoChromeSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.padding,
    this.accent,
    this.style = AppGlassStyle.chrome,
    this.emphasized = false,
    this.boxShadow,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? accent;
  final AppGlassStyle style;
  final bool emphasized;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.accentOf(context);
    final isDark = AppColors.isDark(context);
    final highlight = tint.withValues(
      alpha: isDark
          ? (emphasized ? 0.18 : 0.10)
          : (emphasized ? 0.12 : 0.06),
    );
    final edge = Color.lerp(
      AppColors.cardBorder(context),
      tint,
      emphasized ? 0.28 : 0.12,
    )!;

    return GlassSurface(
      style: style,
      borderRadius: borderRadius,
      border: Border.all(
        color: edge.withValues(alpha: emphasized ? 0.72 : 0.52),
        width: emphasized ? 0.8 : 0.6,
      ),
      boxShadow: boxShadow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: isDark ? 0.045 : 0.34),
              highlight,
              Colors.transparent,
            ],
            stops: const [0, 0.28, 1],
          ),
        ),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// Full-bleed ambient wash used behind root pages. It is deliberately made
/// from broad bands rather than decorative blobs, so content remains readable.
class OrigoAmbientBackdrop extends StatelessWidget {
  const OrigoAmbientBackdrop({
    super.key,
    required this.child,
    this.leadingColor,
    this.trailingColor,
  });

  final Widget child;
  final Color? leadingColor;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    final base = AppColors.scaffold(context);
    final leading = leadingColor ?? AppColors.accentOf(context);
    final trailing = trailingColor ?? Theme.of(context).colorScheme.secondary;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0, 0.34, 0.72, 1],
              colors: [
                Color.lerp(base, leading, 0.16)!,
                base,
                Color.lerp(base, trailing, 0.055)!,
                base,
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 150,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    leading.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
