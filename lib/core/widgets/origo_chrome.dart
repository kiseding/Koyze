import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/effect_policy.dart';
import '../theme/glass_config.dart';
import 'glass_backdrop.dart';

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
    this.blur,
    this.backdrop = true,
    this.solidBehind = false,
    this.shareBackdrop = true,
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

  /// 模糊半径覆盖。传 0 就退化成一块实色面板——没有东西可以采样时
  /// （横屏侧栏左边就是空的）必须这样做，原因见侧栏那边的注释。
  final double? blur;

  /// 是否采样背后的内容做模糊。背后是纯色页面底时为 false：模糊一层纯色
  /// 和直接混出同一个颜色在屏幕上完全一样，却要占一次全屏背景采样。
  ///
  /// 首页那排快捷卡是最典型的例子——一屏十张卡各自抓一次背景，全都在采样
  /// 同一块纯色底。手机上这类多余采样正是滑动掉帧的主因之一。
  ///
  /// 注意它只是「没声明」的意思：虚化档 > 0 时仍会采样，否则这些面对滑杆
  /// 毫无反应。**确定**背后是纯色时请改用 [solidBehind]。
  final bool backdrop;

  /// 背后**确定**只有页面底色，没有滚动内容会经过。见 [GlassSurface.solidBehind]。
  final bool solidBehind;

  /// 是否复用外层 [BackdropGroup] 的采样键。浮在滚动内容上方的搜索框等
  /// chrome 传 false，独立采样已经绘制的列表内容。
  final bool shareBackdrop;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.accentOf(context);

    return GlassSurface(
      style: style,
      borderRadius: borderRadius,
      emphasized: emphasized,
      blur: blur,
      backdrop: backdrop,
      solidBehind: solidBehind,
      shareBackdrop: shareBackdrop,
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

/// Chrome backdrop: a flat tint at whatever opacity the slider says.
///
/// 早先按 6 条窄带做「模糊半径渐变」，想消掉糊边；但每条带都是在已经模糊过的
/// 结果上再采样，叠加后并不是真正的渐变，只是一条条更糊的横条。改成单层
/// [BackdropFilter] 后，边缘由染色层的淡出负责——那才是 iOS 标题栏的做法，
/// 也少采样五次。
///
/// 现在连染色层也不再淡出：设置里选 80%，整条栏就画 80%。留着渐隐的话底边全
/// 透明，平均下来只剩一半出头，看到的永远比滑杆上的数字淡。
class GradientFrost extends StatelessWidget {
  const GradientFrost({
    super.key,
    required this.child,
    this.sigma = 16,
    this.base,
    this.fadeOutFrom,
    this.shareBackdrop = true,
  });

  final Widget child;

  final double sigma;

  /// Tint colour; defaults to the themed bar base.
  final Color? base;

  /// 染色层从哪个比例开始淡出（0~1，沿纵向）。null = 整块保持浓度。
  ///
  /// 根页的 tab 标题栏比栏本身高出一段：多出来的那 28pt 是为了让列表从栏底
  /// 钻出来时不撞上一条硬边。那一段必须淡出，否则底边是一条明显的横线；
  /// 但淡出又不能从栏顶就开始（标题会压到亮色背景上读不清），所以只有下面
  /// 一小截渐变。独立页面的 AppBar 高度就是栏本身，用默认的 null 即可。
  final double? fadeOutFrom;

  /// 是否复用外层采样键。叠在页面玻璃上的控件可独立采样已绘制的内容。
  final bool shareBackdrop;

  @override
  Widget build(BuildContext context) {
    // 顶栏染色浓度吃「界面不透明度」，磨砂吃「虚化」——两档都要随滑杆当场重画。
    //
    // 这里**不**监听 [GlassScrollActivity]：标题栏是常驻 chrome，不跟着手势
    // 变材质。早先 sigma 在滚动期乘过 0.5 的折扣，结果是手指一抬模糊度就
    // 跳一下；而独立页面的标题栏根本不在这套滚动观察范围内（`GlassScrollObserver`
    // 只包了根壳层），同一个组件在两种页面里表现不一样。省下的那点卷积时间
    // 换不来「同一根栏看着会变」，所以标题栏恒定满档。
    return ListenableBuilder(
      listenable: Listenable.merge([
        GlassEffectConfig.surfaceOpacityListenable,
        GlassEffectConfig.surfaceBlurListenable,
      ]),
      builder: (context, _) => _buildTint(context),
    );
  }

  Widget _buildTint(BuildContext context) {
    final tint = base ?? AppGlass.tintBase(context, style: AppGlassStyle.bar);
    // 简化特效时不能只留一层半透明染色：底下的列表文字会清晰地压在标题上，
    // 读起来像标题栏没画完。退回接近不透明的底色。
    // 增强对比度、系统关掉动画同理——见 [prefersFlatSurfaces]。
    final reduce = prefersFlatSurfaces(context) || sigma <= 0;
    final alpha = reduce ? 1.0 : GlassEffectConfig.surfaceAlpha;
    final solidTint = reduce
        ? Color.alphaBlend(
            tint.withValues(alpha: 0.97),
            AppColors.scaffold(context),
          )
        : tint;
    final tintLayer = IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fadeOutFrom == null
              ? solidTint.withValues(alpha: alpha)
              : null,
          gradient: fadeOutFrom == null
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, fadeOutFrom!.clamp(0.0, 1.0), 1],
                  colors: [
                    solidTint.withValues(alpha: alpha),
                    solidTint.withValues(alpha: alpha),
                    solidTint.withValues(alpha: 0),
                  ],
                ),
        ),
      ),
    );
    // 虚化归零时只画染色层，保留用户选择的不透明度。
    final frosted = !reduce && GlassEffectConfig.userBlurEnabled;
    return Stack(
      children: [
        if (frosted)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: GlassBackdrop(
                  // 恒定满档，不乘滚动折扣：见 build 里的说明。
                  sigma: GlassEffectConfig.scaleSurfaceBlur(sigma),
                  saturation: AppGlass.saturate,
                  allowBlur: true,
                  shareBackdrop: shareBackdrop,
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
