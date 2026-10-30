import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'effect_policy.dart';
import 'glass_config.dart';

/// 玻璃材质，照搬 origo-x 的 `GlassControlSurface`。
///
/// 关键差别只有一条：**整块渐变被去掉了**。origo-x 的玻璃是一层单色低 alpha
/// 染色 + 高斯模糊 + 一条细边缘高光；斜向的白色渐变（左上亮到右下暗）正是
/// "复古玻璃"的来源——它把面板画成一片有高光的塑料。去掉渐变后，面板的明暗
/// 完全来自背后内容被模糊后的颜色，这就是 iOS 那种透明玻璃。
enum AppGlassStyle {
  /// 导航栏 / 底部 dock / 迷你播放条：最宽的悬浮面。
  bar,

  /// 弹窗与面板：低透明度、无投影。
  sheet,

  /// 卡片、提示条等常规玻璃面。
  regular,

  /// 压在封面或其它玻璃上的小控件。
  chrome,
}

abstract final class AppGlass {
  /// 模糊半径统一取自 [GlassEffectConfig]，性能模式下会整体缩放。
  static double get blurBar => GlassEffectConfig.navigationBarBlur;
  static double get blurSheet => GlassEffectConfig.modalBlur;
  static double get blurRegular => GlassEffectConfig.lightCardBlur;
  static double get blurChrome => GlassEffectConfig.appBarBlur;

  /// 饱和度只轻微提一点：完全不加会糊成灰，加多了又变彩色塑料。
  static const double saturate = 1.15;

  static double blurFor(AppGlassStyle style) => switch (style) {
    AppGlassStyle.bar => blurBar,
    AppGlassStyle.sheet => blurSheet,
    AppGlassStyle.regular => blurRegular,
    AppGlassStyle.chrome => blurChrome,
  };

  /// 玻璃的基色（不含 alpha）。
  ///
  /// 固定中性色，不再往 primary 上染：换主题色时玻璃、卡片、弹窗都保持同一
  /// 张灰阶，只有关键元素（选中项、播放键、主按钮）才跟强调色走。
  static Color tintBase(
    BuildContext context, {
    AppGlassStyle style = AppGlassStyle.regular,
  }) {
    final isDark = AppColors.isDark(context);
    return switch (style) {
      AppGlassStyle.chrome =>
        isDark ? const Color(0xFF1C1F25) : const Color(0xFFF7F7FB),
      _ => isDark ? const Color(0xFF14161B) : Colors.white,
    };
  }

  /// 染色透明度：深色 0.30、浅色 0.60（origo 的 chrome 档位）。
  static (double, double) overlayAlphas(
    BuildContext context, {
    AppGlassStyle style = AppGlassStyle.regular,
    bool emphasized = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final alpha =
        GlassEffectConfig.chromeOpacityFor(scheme.brightness) +
        (emphasized ? 0.06 : 0);
    final clamped = alpha.clamp(0.0, 1.0);
    return (clamped, clamped);
  }

  /// 玻璃面最终颜色：单色，不是渐变。
  static Color fillColor(
    BuildContext context, {
    AppGlassStyle style = AppGlassStyle.regular,
    bool emphasized = false,
    double alphaScale = 1,
  }) {
    final base = tintBase(context, style: style);
    final isDark = AppColors.isDark(context);
    final lifted = emphasized
        ? Color.lerp(base, Colors.white, isDark ? 0.05 : 0.14)!
        : base;
    final (alpha, _) = overlayAlphas(
      context,
      style: style,
      emphasized: emphasized,
    );
    return lifted.withValues(alpha: (alpha * alphaScale).clamp(0.0, 1.0));
  }

  /// 实色代替（提示条、无模糊回退）。
  static Color fill(
    BuildContext context, {
    AppGlassStyle style = AppGlassStyle.regular,
  }) => fillColor(context, style: style);

  /// 细边缘：深色是反光，浅色是分组边框。始终中性，不跟着强调色走。
  static BorderSide hairline(BuildContext context, {bool emphasized = false}) {
    final isDark = AppColors.isDark(context);
    final source = AppColors.cardBorder(context);
    final highlighted = Color.lerp(
      source,
      Colors.white,
      isDark ? 0.24 : 0.16,
    )!;
    return BorderSide(
      color: highlighted.withValues(alpha: emphasized ? 0.52 : 0.38),
      width: 0.8,
    );
  }

  /// 悬浮投影。中性黑，浅色下也不用强调色——彩色投影会让玻璃看起来是
  /// 一块染了色的小卡，而不是透明的介质。
  static List<BoxShadow> shadowFor(
    BuildContext context, {
    AppGlassStyle style = AppGlassStyle.regular,
    bool emphasized = false,
    Color? accent,
  }) {
    final isDark = AppColors.isDark(context);
    final color = isDark
        ? Colors.black.withValues(alpha: emphasized ? 0.22 : 0.14)
        : Colors.black.withValues(alpha: emphasized ? 0.10 : 0.06);
    return [
      BoxShadow(
        color: color,
        blurRadius: emphasized ? 22 : 16,
        offset: Offset(0, emphasized ? 8 : 5),
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

  /// dock 专用：模糊更宽、饱和度更高，底下的内容才不会糊成灰浆。
  static ImageFilter liquidFilter({double blur = 26, double saturation = 1.45}) {
    return ImageFilter.compose(
      outer: ImageFilter.blur(
        sigmaX: blur,
        sigmaY: blur,
        tileMode: TileMode.mirror,
      ),
      inner: ColorFilter.matrix(_saturationMatrix(saturation)),
    );
  }

  /// 5x4 颜色矩阵，围绕 Rec.709 亮度缩放饱和度。
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

/// iOS 式渐隐：顶栏向下淡出、底栏向上淡出，滚动内容不会撞上一条硬边。
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
    this.backdrop = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  /// 可选的基色提示。只用来给某一块面一点色相，透明度仍由 [AppGlassStyle]
  /// 决定，避免一块面比旁边的更实。
  final Color? color;
  final Border? border;
  final AppGlassStyle style;
  final double? blur;
  final List<BoxShadow>? boxShadow;
  final AppGlassFade fade;

  /// 为 false 时不叠饱和度矩阵，滚动时每帧少一次全栏滤镜。
  final bool vivid;

  /// 更亮的边和更深的投影，用于悬浮 chrome。
  final bool emphasized;

  /// 整体透明度倍率（0–1）。
  final double alphaScale;

  /// 是否采样背后的内容做模糊。
  ///
  /// 为 false 时直接按玻璃底色与页面底色混出一块实色——背后是纯色页面底
  /// 的场合（设置页分区卡片），模糊采到的就是同一个颜色，画出来一模一样，
  /// 却省掉一整条全宽 [BackdropFilter]。那种卡片一屏能同时出现四五张，
  /// 滚动时每帧都要重算一遍模糊，正是掉帧的来源。
  ///
  /// 只对「背后是纯色」的大块面成立：浮在封面、列表内容上的胶囊、弹窗
  /// 仍然要真模糊。为 false 时 [fade] 不生效。
  final bool backdrop;

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
    // 玻璃是有底色的 DecoratedBox，ListTile 的水波纹要画在最近的 Material 上。
    // 不给它一层透明 Material，Flutter 会直接断言"ink 可能不可见"，而且点击
    // 反馈会被这层底色盖住。
    final material = Material(type: MaterialType.transparency, child: content);
    // 简化特效、增强对比度、系统关掉动画：这三种情况都不该再为「看见背后」
    // 付出每帧一次全宽采样，直接按底色混出一块实色。
    if (prefersFlatSurfaces(context) || sigma <= 0) {
      final opaque = Color.alphaBlend(
        base.withValues(alpha: 0.94),
        AppColors.scaffold(context),
      );
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
          child: material,
        ),
      );
    }
    if (!backdrop) {
      // 背后是纯色页面底：把底色混上去和「模糊一层纯色再混」是同一个结果，
      // 但不用每帧做一次全宽 BackdropFilter + 饱和度矩阵。
      final flat = Color.alphaBlend(base, AppColors.scaffold(context));
      return DecoratedBox(
        decoration: BoxDecoration(
          color: flat,
          borderRadius: radius,
          border: side,
          boxShadow: boxShadow ?? const <BoxShadow>[],
        ),
        child: ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: material,
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
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: radius,
                  border: side,
                ),
                child: material,
              ),
            )
          : _FadingFrost(
              sigma: sigma,
              fade: fade,
              base: base,
              radius: radius,
              border: side,
              vivid: vivid,
              child: material,
            ),
    );
    final shadows =
        boxShadow ??
        (style == AppGlassStyle.bar ||
                (emphasized && style != AppGlassStyle.sheet)
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

  /// 玻璃面颜色：[color] 只做轻微色相偏移，不接管透明度。
  Color _baseColor(BuildContext context) {
    final themed = AppGlass.fillColor(
      context,
      style: style,
      emphasized: emphasized,
      alphaScale: alphaScale,
    );
    if (color == null) return themed;
    final nudge = AppColors.isDark(context) ? 0.05 : 0.04;
    return Color.lerp(themed, color!.withValues(alpha: themed.a), nudge)!;
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
    required this.radius,
    required this.border,
    required this.vivid,
    required this.child,
  });

  final double sigma;
  final AppGlassFade fade;
  final Color base;
  final BorderRadius radius;
  final Border border;
  final bool vivid;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final down = fade == AppGlassFade.down;
    // 靠近 chrome 的一端保持实，朝滚动边淡出，内容不会以一条线结尾。
    final solid = base;
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
