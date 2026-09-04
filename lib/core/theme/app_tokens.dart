import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// iOS-style frosted glass. Matches system materials more closely than a
/// plain blur + near-opaque fill:
/// - stronger blur
/// - slight saturation boost (UIBlurEffect)
/// - thin vibrancy tint, not a solid card
/// - 0.5pt hairline highlight
enum AppGlassStyle {
  /// Nav / tab / mini player: ultra-thin material.
  bar,

  /// Sheets, dialogs, toasts: regular material.
  regular,

  /// Compact controls sitting on artwork: thin material.
  chrome,
}

abstract final class AppGlass {
  static const double blurBar = 36;
  static const double blurRegular = 50;
  static const double blurChrome = 28;
  static const double saturate = 1.8;

  static double blurFor(AppGlassStyle style) => switch (style) {
    AppGlassStyle.bar => blurBar,
    AppGlassStyle.regular => blurRegular,
    AppGlassStyle.chrome => blurChrome,
  };

  static Color fill(BuildContext context, {AppGlassStyle style = AppGlassStyle.regular}) {
    final isDark = AppColors.isDark(context);
    final alpha = switch (style) {
      AppGlassStyle.bar => isDark ? 0.58 : 0.72,
      AppGlassStyle.regular => isDark ? 0.62 : 0.78,
      AppGlassStyle.chrome => isDark ? 0.42 : 0.55,
    };
    return (isDark ? const Color(0xFF1C1C1E) : Colors.white).withValues(
      alpha: alpha,
    );
  }

  static BorderSide hairline(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return BorderSide(
      color: isDark ? const Color(0x33FFFFFF) : const Color(0x3DFFFFFF),
      width: 0.5,
    );
  }

  static ImageFilter filterFor(AppGlassStyle style) {
    final sigma = blurFor(style);
    return ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
      inner: ColorFilter.matrix(_saturationMatrix(saturate)),
    );
  }

  /// 5x4 color matrix that scales saturation around Rec.709 luma.
  static List<double> _saturationMatrix(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final ir = 1 - s;
    return <double>[
      ir * r + s, ir * g,     ir * b,     0, 0,
      ir * r,     ir * g + s, ir * b,     0, 0,
      ir * r,     ir * g,     ir * b + s, 0, 0,
      0,          0,          0,          1, 0,
    ];
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
    this.style = AppGlassStyle.regular,
    this.blur,
    this.boxShadow,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Border? border;
  final AppGlassStyle style;
  final double? blur;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    final sigma = blur ?? AppGlass.blurFor(style);
    final filter = blur == null
        ? AppGlass.filterFor(style)
        : ImageFilter.compose(
            outer: ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.clamp,
            ),
            inner: ColorFilter.matrix(AppGlass._saturationMatrix(AppGlass.saturate)),
          );
    final glass = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: filter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? AppGlass.fill(context, style: style),
            borderRadius: radius,
            border: border ?? Border.fromBorderSide(AppGlass.hairline(context)),
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
