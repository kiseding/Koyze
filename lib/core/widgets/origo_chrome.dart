import 'dart:ui';

import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../performance/low_memory.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Shared chrome surface for floating controls.
///
/// The gradient, tint and shadow all live in [GlassSurface]; this widget only
/// decides how strongly the accent colour should register. Keeping one source
/// of truth is what stops stacked surfaces from turning opaque white.
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

  /// Accent used for the edge and the floating shadow. Defaults to the theme
  /// primary; the base tint itself stays neutral so a page of cards does not
  /// become a patchwork of coloured panels.
  final Color? accent;
  final AppGlassStyle style;
  final bool emphasized;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.accentOf(context);

    return GlassSurface(
      style: style,
      borderRadius: borderRadius,
      emphasized: emphasized,
      border: Border.fromBorderSide(
        AppGlass.hairline(context, emphasized: emphasized),
      ),
      boxShadow:
          boxShadow ??
          (emphasized
              ? AppGlass.shadowFor(
                  context,
                  style: style,
                  emphasized: true,
                  accent: tint,
                )
              : null),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

/// Compact glass choice control shared by settings and data screens.
///
/// It keeps the same optical weight as the floating panels while remaining
/// small enough for wrapped service lists and segmented dashboard controls.
class KoyzeChoicePill extends StatelessWidget {
  const KoyzeChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
    this.dense = false,
    this.padding,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool dense;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final disabled = onPressed == null;
    final radius = BorderRadius.circular(dense ? 12 : 14);
    final foreground = selected
        ? accent.withValues(alpha: disabled ? 0.58 : 1)
        : AppColors.onScaffold(context).withValues(alpha: disabled ? 0.52 : 1);

    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: label,
      child: AnimatedContainer(
        duration: motionDuration(context, MotionDuration.micro),
        curve: MotionCurve.easeOut,
        constraints: BoxConstraints(minHeight: dense ? 34 : 40),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: disabled ? 0.09 : 0.14)
              : AppColors.fill(context),
          borderRadius: radius,
          border: Border.fromBorderSide(
            AppGlass.hairline(context, emphasized: selected),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Padding(
              padding:
                  padding ??
                  EdgeInsets.symmetric(
                    horizontal: dense ? 10 : 12,
                    vertical: dense ? 7 : 9,
                  ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: dense ? 16 : 18, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: dense ? 11.5 : 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-bleed ambient wash behind root pages.
///
/// Built the way Origo builds page backgrounds: the surface blended toward the
/// accent at the top, a second, weaker blend in the middle, then the plain
/// surface. Three smooth stops, no overlay band with a visible edge.
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
    final isDark = AppColors.isDark(context);
    final base = AppColors.scaffold(context);
    final leading = leadingColor ?? AppColors.accentOf(context);
    final trailing = trailingColor ?? Theme.of(context).colorScheme.secondary;
    // The wash is a hint of the accent near the chrome, not a page-wide tint:
    // a wide tint at high alpha turns black into green fog and white into
    // grey-green paper.
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(color: base)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomCenter,
              stops: const [0, 0.44, 1],
              colors: [
                Color.alphaBlend(
                  leading.withValues(alpha: isDark ? 0.11 : 0.040),
                  base,
                ),
                Color.alphaBlend(
                  trailing.withValues(alpha: isDark ? 0.045 : 0.018),
                  base,
                ),
                base,
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Chrome backdrop whose blur radius tapers to zero toward the bottom.
///
/// A uniform `BackdropFilter` over a tall header leaves a hard edge where the
/// blur stops, which reads as a grey band. Stacking narrow filters with a
/// decreasing radius — the fallback Origo uses when shader filters are absent
/// — costs a handful of extra layers but removes that edge entirely.
class GradientFrost extends StatelessWidget {
  const GradientFrost({
    super.key,
    required this.child,
    this.height,
    this.bands = 6,
    this.sigma = 16,
    this.base,
    this.leadingAlpha,
  });

  final Widget child;

  /// Total frosted height. Falls back to the incoming constraint.
  final double? height;

  /// Narrow filters approximating the radius curve. Kept low: every band is a
  /// full backdrop sample.
  final int bands;
  final double sigma;

  /// Tint colour; defaults to the themed bar base.
  final Color? base;

  /// Opacity at the top edge. Defaults to the dark/light bar value.
  final double? leadingAlpha;

  @override
  Widget build(BuildContext context) {
    final tint = base ?? AppGlass.tintBase(context, style: AppGlassStyle.bar);
    final (defaultAlpha, _) = AppGlass.overlayAlphas(
      context,
      style: AppGlassStyle.bar,
    );
    final alpha = leadingAlpha ?? defaultAlpha;
    return LayoutBuilder(
      builder: (context, constraints) {
        final frostedHeight = height ?? constraints.maxHeight;
        final safeHeight = frostedHeight.isFinite && frostedHeight > 0
            ? frostedHeight
            : 0.0;
        final tintLayer = IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.58, 1],
                colors: [
                  tint.withValues(alpha: alpha),
                  tint.withValues(alpha: alpha * 0.52),
                  tint.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        );
        if (LowMemory.active || safeHeight <= 0 || sigma <= 0) {
          return Stack(
            children: [
              Positioned.fill(child: tintLayer),
              child,
            ],
          );
        }
        // Bottom-up: a stronger band must not sample through a weaker one.
        final bandCount = bands.clamp(1, 24);
        final bandHeight = safeHeight / bandCount;
        return Stack(
          children: [
            for (var i = bandCount - 1; i >= 0; i--)
              Positioned(
                top: bandHeight * i,
                height: bandHeight,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: sigma * (1 - (i + 0.5) / bandCount),
                        sigmaY: sigma * (1 - (i + 0.5) / bandCount),
                        tileMode: TileMode.mirror,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            Positioned.fill(child: tintLayer),
            child,
          ],
        );
      },
    );
  }
}
