import 'dart:ui';

import 'package:flutter/material.dart';

import '../performance/low_memory.dart';
import 'app_colors.dart';

/// Glass materials, modelled on Origo-x's chrome.
///
/// The material is a single gradient laid over a modest blur — never a solid
/// fill plus a second white wash. Three rules keep it from looking like
/// painted plastic:
/// - the base colour is the theme surface with a light primary tint;
/// - both ends of the gradient stay below ~0.85 alpha so the backdrop shows;
/// - shadows borrow the accent hue in light theme instead of neutral black.
enum AppGlassStyle {
  /// Nav / tab / mini player: the widest surfaces.
  bar,

  /// Sheets, dialogs, toasts.
  regular,

  /// Compact controls sitting on artwork or other glass.
  chrome,
}

abstract final class AppGlass {
  // Blur is deliberately lower than a "frosted panel" default: heavy blur
  // removes the colour behind the glass and the result reads as grey.
  static const double blurBar = 20;
  static const double blurRegular = 26;
  static const double blurChrome = 14;

  /// 1.8 over-saturates low-alpha glass; 1.3 keeps the tint believable.
  static const double saturate = 1.3;

  static double blurFor(AppGlassStyle style) => switch (style) {
    AppGlassStyle.bar => blurBar,
    AppGlassStyle.regular => blurRegular,
    AppGlassStyle.chrome => blurChrome,
  };

  /// Opaque base colour behind the gradient.
  ///
  /// Origo tints chrome with `surface` lerped toward `primary`, so switching
  /// the accent colour re-tints every glass surface instead of leaving a
  /// fixed white card behind.
  static Color tintBase(
    BuildContext context, {
    AppGlassStyle style = AppGlassStyle.regular,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = AppColors.isDark(context);
    final card = AppColors.card(context);
    // Wider chrome takes a little more tint than a small control, otherwise
    // large surfaces look washed out next to compact ones. Both values stay
    // low: a green-tinted white card on a white page reads as dirty.
    final strength = switch (style) {
      AppGlassStyle.bar => isDark ? 0.040 : 0.030,
      AppGlassStyle.regular => isDark ? 0.035 : 0.034,
      AppGlassStyle.chrome => isDark ? 0.030 : 0.026,
    };
    final toned = Color.lerp(card, scheme.primary, strength)!;
    if (!isDark) return toned;
    // Pure #1C1C1E disappears on a black background; lift it just enough for
    // the glass edge to register without turning the panel grey.
    return Color.lerp(toned, const Color(0xFF2A2A2C), 0.38)!;
  }

  /// Opacity of the leading (top-left) and trailing (bottom-right) ends.
  static (double, double) overlayAlphas(
    BuildContext context, {
    AppGlassStyle style = AppGlassStyle.regular,
    bool emphasized = false,
  }) {
    final isDark = AppColors.isDark(context);
    return switch (style) {
      AppGlassStyle.bar =>
        isDark
            ? (emphasized ? 0.58 : 0.44, emphasized ? 0.42 : 0.30)
            : (emphasized ? 0.80 : 0.66, emphasized ? 0.62 : 0.46),
      AppGlassStyle.regular =>
        isDark
            ? (emphasized ? 0.66 : 0.52, emphasized ? 0.50 : 0.36)
            : (emphasized ? 0.80 : 0.70, emphasized ? 0.64 : 0.52),
      AppGlassStyle.chrome =>
        isDark
            ? (emphasized ? 0.50 : 0.36, emphasized ? 0.36 : 0.24)
            : (emphasized ? 0.74 : 0.58, emphasized ? 0.56 : 0.42),
    };
  }

  /// Flat colour for callers that need a solid stand-in (toasts, opaque
  /// fallbacks). Keeps the tint but resolves to the gradient's strong end.
  static Color fill(
    BuildContext context, {
    AppGlassStyle style = AppGlassStyle.regular,
  }) {
    final (leading, _) = overlayAlphas(context, style: style);
    return tintBase(context, style: style).withValues(alpha: leading);
  }

  /// Hairline edge: reflected light in dark theme, a grouped-cell rule in
  /// light theme. A white edge on a near-white page simply disappears.
  static BorderSide hairline(BuildContext context, {bool emphasized = false}) {
    final scheme = Theme.of(context).colorScheme;
    if (!AppColors.isDark(context)) {
      final color = Color.lerp(
        const Color(0xFF3C3C43),
        scheme.primary,
        emphasized ? 0.28 : 0.06,
      )!;
      return BorderSide(
        color: color.withValues(alpha: emphasized ? 0.22 : 0.13),
        width: emphasized ? 0.9 : 0.7,
      );
    }
    final color = Color.lerp(
      Colors.white,
      scheme.primary,
      emphasized ? 0.55 : 0.14,
    )!;
    return BorderSide(
      color: color.withValues(alpha: emphasized ? 0.34 : 0.18),
      width: emphasized ? 0.9 : 0.7,
    );
  }

  /// Floating shadow. Light theme leans on the accent so the shadow belongs
  /// to the palette; a neutral black shadow over the warm backdrop looks dirty.
  static List<BoxShadow> shadowFor(
    BuildContext context, {
    AppGlassStyle style = AppGlassStyle.regular,
    bool emphasized = false,
    Color? accent,
  }) {
    final isDark = AppColors.isDark(context);
    final source = accent ?? Theme.of(context).colorScheme.primary;
    final color = isDark
        ? Colors.black.withValues(alpha: emphasized ? 0.34 : 0.22)
        : Color.lerp(
            source,
            Colors.black,
            0.45,
          )!.withValues(alpha: emphasized ? 0.16 : 0.10);
    return [
      BoxShadow(
        color: color,
        blurRadius: emphasized ? 28 : 18,
        offset: Offset(0, emphasized ? 12 : 6),
      ),
    ];
  }

  static ImageFilter filterFor(AppGlassStyle style) {
    final sigma = blurFor(style);
    return ImageFilter.compose(
      outer: ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.mirror,
      ),
      inner: ColorFilter.matrix(_saturationMatrix(saturate)),
    );
  }

  /// Filter for the liquid-glass dock: a wider blur than the cards use, with
  /// extra saturation so the colours that survive the blur read as colour and
  /// not as grey mush. Content stays recognisable underneath — that is the
  /// whole point of the tab bar sitting on top of the page instead of beside
  /// it.
  static ImageFilter liquidFilter({
    double blur = 26,
    double saturation = 1.7,
  }) {
    return ImageFilter.compose(
      outer: ImageFilter.blur(
        sigmaX: blur,
        sigmaY: blur,
        tileMode: TileMode.mirror,
      ),
      inner: ColorFilter.matrix(_saturationMatrix(saturation)),
    );
  }

  /// 5x4 color matrix that scales saturation around Rec.709 luma.
  static List<double> _saturationMatrix(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final ir = 1 - s;
    return <double>[
      ir * r + s,
      ir * g,
      ir * b,
      0,
      0,
      ir * r,
      ir * g + s,
      ir * b,
      0,
      0,
      ir * r,
      ir * g,
      ir * b + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
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
    this.vivid = true,
    this.emphasized = false,
    this.alphaScale = 1,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Optional base tint. Its RGB replaces the themed base; opacity is still
  /// governed by [AppGlassStyle] so every surface stays equally translucent.
  final Color? color;
  final Border? border;
  final AppGlassStyle style;
  final double? blur;
  final List<BoxShadow>? boxShadow;
  final AppGlassFade fade;

  /// 为 false 时只做模糊，不再叠饱和度矩阵。滚动内容从栏下穿过时，
  /// 每帧少一次全栏滤镜。
  final bool vivid;

  /// Brighter edge and a deeper shadow, used by floating chrome.
  final bool emphasized;

  /// 整体透明度倍率（0–1）。近全屏的面板压在页面上时，0.7 的基底会把
  /// 底层完全糊成一块色；压到 0.85 左右仍能透出页面结构。
  final double alphaScale;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    final sigma = blur ?? AppGlass.blurFor(style);
    final base = _baseColor(context);
    final side =
        border ??
        Border.fromBorderSide(
          AppGlass.hairline(context, emphasized: emphasized),
        );
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    if (LowMemory.active) {
      final surface = AppColors.card(context);
      final opaque = Color.alphaBlend(base.withValues(alpha: 0.94), surface);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: opaque,
          borderRadius: radius,
          border: side,
          boxShadow: boxShadow ?? const <BoxShadow>[],
        ),
        child: ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      );
    }
    final glass = ClipRRect(
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: fade == AppGlassFade.none
          ? BackdropFilter(
              filter: _filter(sigma, vivid: vivid),
              child: DecoratedBox(
                decoration: _decoration(context, radius: radius, border: side),
                child: content,
              ),
            )
          : _FadingFrost(
              sigma: sigma,
              fade: fade,
              base: base,
              leadingAlpha: _leadingAlpha(context),
              radius: radius,
              border: side,
              vivid: vivid,
              child: content,
            ),
    );
    final shadows =
        boxShadow ??
        (style == AppGlassStyle.bar || emphasized
            ? AppGlass.shadowFor(
                context,
                style: style,
                emphasized: emphasized,
                accent: color,
              )
            : const <BoxShadow>[]);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
      child: glass,
    );
  }

  /// Base tint, optionally nudged by [color]'s hue.
  Color _baseColor(BuildContext context) {
    final themed = AppGlass.tintBase(context, style: style);
    if (color == null) return themed;
    // Replacing the base with the accent turns every card into its own
    // saturated panel, which reads as a patchwork. Nudge instead — just
    // enough that a row of cards shares a family resemblance.
    final nudge = AppColors.isDark(context) ? 0.045 : 0.030;
    return Color.lerp(themed, color!, nudge)!;
  }

  double _leadingAlpha(BuildContext context) {
    final (leading, _) = AppGlass.overlayAlphas(
      context,
      style: style,
      emphasized: emphasized,
    );
    return (leading * alphaScale).clamp(0.0, 1.0);
  }

  /// One gradient, top-left highlight into the base tint. No second wash.
  BoxDecoration _decoration(
    BuildContext context, {
    required BorderRadius radius,
    required Border border,
  }) {
    final isDark = AppColors.isDark(context);
    final base = _baseColor(context);
    final (leading, trailing) = AppGlass.overlayAlphas(
      context,
      style: style,
      emphasized: emphasized,
    );
    final lead = (leading * alphaScale).clamp(0.0, 1.0);
    final trail = (trailing * alphaScale).clamp(0.0, 1.0);
    final highlight = Color.lerp(base, Colors.white, isDark ? 0.16 : 0.28)!;
    return BoxDecoration(
      borderRadius: radius,
      border: border,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          highlight.withValues(alpha: lead),
          base.withValues(alpha: trail),
        ],
      ),
    );
  }

  static ImageFilter _filter(double sigma, {bool vivid = true}) {
    final blur = ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.mirror,
    );
    if (!vivid) return blur;
    return ImageFilter.compose(
      outer: blur,
      inner: ColorFilter.matrix(AppGlass._saturationMatrix(AppGlass.saturate)),
    );
  }
}

class _FadingFrost extends StatelessWidget {
  const _FadingFrost({
    required this.sigma,
    required this.fade,
    required this.base,
    required this.leadingAlpha,
    required this.radius,
    required this.border,
    required this.vivid,
    required this.child,
  });

  final double sigma;
  final AppGlassFade fade;
  final Color base;
  final double leadingAlpha;
  final BorderRadius radius;
  final Border border;
  final bool vivid;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final down = fade == AppGlassFade.down;
    // Solid at the chrome end so the title/status area stays readable, clear
    // toward the scrolling edge so content does not end on a hard band.
    final solid = base.withValues(alpha: leadingAlpha);
    final clear = base.withValues(alpha: 0);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: BackdropFilter(
                filter: GlassSurface._filter(sigma, vivid: vivid),
                child: const ColoredBox(color: Color(0x00000000)),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              tileMode: TileMode.clamp,
              colors: down ? [solid, clear] : [clear, solid],
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
