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
/// 只画一层中性页面底色。以前这里会在顶部掺一点强调色，换主题色时整页跟着
/// 变蓝/变绿，看起来像全局染色；现在强调色只出现在关键元素上，页面底色
/// 保持中性。参数保留是为了不惊动调用点。
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
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: AppColors.scaffold(context)),
        ),
        child,
      ],
    );
  }
}

/// Chrome backdrop: one full-width blur with the tint fading out downward.
///
/// 早先按 6 条窄带做「模糊半径渐变」，想消掉糊边；但每条带都是在已经模糊过的
/// 结果上再采样，叠加后并不是真正的渐变，只是一条条更糊的横条。改成单层
/// [BackdropFilter] 后，边缘由染色层的淡出负责——那才是 iOS 标题栏的做法，
/// 也少采样五次。
class GradientFrost extends StatelessWidget {
  const GradientFrost({
    super.key,
    required this.child,
    this.sigma = 16,
    this.base,
    this.leadingAlpha,
  });

  final Widget child;

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
    // 简化特效时不能只留一层 18% 的染色：底下的列表文字会清晰地压在标题上，
    // 读起来像标题栏没画完。退回接近不透明的底色，只在最后 15% 淡出。
    final reduce = LowMemory.active || sigma <= 0;
    final solidTint = reduce
        ? Color.alphaBlend(
            tint.withValues(alpha: 0.97),
            AppColors.scaffold(context),
          )
        : tint;
    final alpha = reduce ? 1.0 : (leadingAlpha ?? defaultAlpha);
    final tintLayer = IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: reduce ? const [0, 0.85, 1] : const [0, 0.58, 1],
            colors: [
              solidTint.withValues(alpha: alpha),
              solidTint.withValues(alpha: alpha * (reduce ? 0.92 : 0.52)),
              solidTint.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
    return Stack(
      children: [
        // 整条栏共用一个 BackdropFilter。之前按 6 条横带做「渐变模糊」，
        // 但每次采样都建立在上一层已模糊的结果上，叠加后并没有变清楚，反而
        // 在真机上出现条带接缝；一条完整的模糊配合染色淡出更接近 iOS。
        if (!reduce)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: sigma,
                    sigmaY: sigma,
                    tileMode: TileMode.mirror,
                  ),
                  child: const ColoredBox(color: Color(0x00000000)),
                ),
              ),
            ),
          ),
        Positioned.fill(child: tintLayer),
        child,
      ],
    );
  }
}
