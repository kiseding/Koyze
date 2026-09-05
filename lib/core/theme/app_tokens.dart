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

/// iOS navigation chrome fades frost toward the scrolling content:
/// top bars are stronger at the bottom edge, tab bars at the top edge.
enum AppGlassFade { none, down, up }

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
    this.fade = AppGlassFade.none,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Border? border;
  final AppGlassStyle style;
  final double? blur;
  final List<BoxShadow>? boxShadow;
  final AppGlassFade fade;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    final sigma = blur ?? AppGlass.blurFor(style);
    final fill = color ?? AppGlass.fill(context, style: style);
    final side = border ?? Border.fromBorderSide(AppGlass.hairline(context));
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    final glass = ClipRRect(
      borderRadius: radius,
      child: fade == AppGlassFade.none
          ? BackdropFilter(
              filter: _filter(sigma),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: radius,
                  border: side,
                ),
                child: content,
              ),
            )
          : _FadingFrost(
              sigma: sigma,
              fade: fade,
              fill: fill,
              radius: radius,
              border: side,
              child: content,
            ),
    );
    if (boxShadow == null || boxShadow!.isEmpty) return glass;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: boxShadow),
      child: glass,
    );
  }

  static ImageFilter _filter(double sigma) => ImageFilter.compose(
    outer: ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.clamp,
    ),
    inner: ColorFilter.matrix(AppGlass._saturationMatrix(AppGlass.saturate)),
  );
}

class _FadingFrost extends StatelessWidget {
  const _FadingFrost({
    required this.sigma,
    required this.fade,
    required this.fill,
    required this.radius,
    required this.border,
    required this.child,
  });

  final double sigma;
  final AppGlassFade fade;
  final Color fill;
  final BorderRadius radius;
  final Border border;
  final Widget child;

  // Keep the toolbar body fully frosted; only the last ~28% fades into the list.
  static const _stops = <double>[0.0, 0.72, 0.86, 1.0];
  static const _strengths = <double>[1.0, 1.0, 0.55, 0.0];

  @override
  Widget build(BuildContext context) {
    final down = fade == AppGlassFade.down;
    final alpha = fill.a;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < _stops.length - 1; i++)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: down ? Alignment.topCenter : Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: _stops[i + 1],
                  widthFactor: 1,
                  alignment: down
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: GlassSurface._filter(sigma * _strengths[i]),
                      child: const ColoredBox(color: Color(0x00000000)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: down
                  ? [
                      fill,
                      fill,
                      fill.withValues(alpha: alpha * 0.55),
                      fill.withValues(alpha: 0),
                    ]
                  : [
                      fill.withValues(alpha: 0),
                      fill.withValues(alpha: alpha * 0.55),
                      fill,
                      fill,
                    ],
              stops: down
                  ? const [0.0, 0.72, 0.86, 1.0]
                  : const [0.0, 0.14, 0.28, 1.0],
            ),
            borderRadius: radius,
            border: border,
          ),
          child: child,
        ),
      ],
    );
  }
}
