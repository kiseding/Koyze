import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../performance/low_memory.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Koyze 的模态语言：一层压暗 + 磨砂的背景，一块浮在上面的玻璃面板。
///
/// Material 默认对话框只有一个淡入的不透明纸片，放在这套玻璃界面里会像
/// 贴上去的贴纸。这里改成 Origo-x 的做法：
/// - 遮罩先压暗再模糊，底层页面退到后面但保留颜色；
/// - 面板从 92% 弹到 100%，用带轻微过冲的曲线，收起时直接走 easeIn；
/// - 面板用与 Dock / 弹窗同一套 [GlassSurface]，圆角、边线、投影全部走 token。
Future<T?> showKoyzeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
}) {
  final isDark = AppColors.isDark(context);
  final reduce =
      (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
      LowMemory.active;
  final scrim = (isDark ? Colors.black : const Color(0xFF11131A)).withValues(
    alpha: isDark ? 0.26 : 0.12,
  );
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: reduce ? Duration.zero : MotionDuration.dialog,
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, animation, _, child) {
      if (reduce) {
        return Stack(
          fit: StackFit.expand,
          children: [scrimLayer(scrim), child],
        );
      }
      final pop = CurvedAnimation(
        parent: animation,
        curve: MotionCurve.dialogIn,
        reverseCurve: MotionCurve.easeIn,
      );
      final veil = CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.55, curve: Curves.easeOut),
        reverseCurve: Curves.easeIn,
      );
      return AnimatedBuilder(
        animation: pop,
        builder: (context, _) {
          final t = pop.value;
          final f = veil.value.clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (!LowMemory.active && t > 0.01)
                Positioned.fill(
                  child: IgnorePointer(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 12 * t,
                        sigmaY: 12 * t,
                        tileMode: TileMode.mirror,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: scrim.withValues(alpha: scrim.a * f),
                  ),
                ),
              ),
              Opacity(
                opacity: f.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 16 * (1 - t)),
                  child: Transform.scale(
                    scale: 0.92 + 0.08 * t,
                    alignment: Alignment.center,
                    child: child,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

Widget scrimLayer(Color scrim) => Positioned.fill(
  child: IgnorePointer(child: ColoredBox(color: scrim)),
);

/// 玻璃对话框面板。
///
/// 参数刻意与 `AlertDialog` 保持同名，调用点从系统弹窗迁过来不需要重排
/// 布局；[backgroundColor] 只用来微调玻璃基底，不再提供实色底，
/// [shape] 仅在需要非默认圆角时生效。
class KoyzeDialog extends StatelessWidget {
  const KoyzeDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 28,
      vertical: 36,
    ),
    this.contentPadding,
    this.actionsPadding,
    this.actionsAlignment = MainAxisAlignment.end,
    this.scrollable = false,
    this.maxWidth = 400,
    this.backgroundColor,
    this.shape,
    this.clipBehavior,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry insetPadding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;
  final MainAxisAlignment actionsAlignment;
  final bool scrollable;
  final double maxWidth;

  /// Tint hint for the glass base. A solid fill would hide the blurred page
  /// behind the panel, which is the whole point of the material.
  final Color? backgroundColor;

  /// Optional corner override; defaults to the 26pt modal radius.
  final ShapeBorder? shape;
  final Clip? clipBehavior;

  @override
  Widget build(BuildContext context) {
    final radius = _radius(shape);
    final media = MediaQuery.sizeOf(context);
    // 键盘弹起时要把面板整体顶上去，否则带输入框的弹窗会被输入法盖住。
    final insets = insetPadding.resolve(Directionality.of(context));
    final padding = insets.add(
      EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    );
    final maxHeight = (media.height - padding.vertical).clamp(
      160.0,
      media.height,
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (icon != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: _IconBadge(icon: icon!),
          ),
          const SizedBox(height: 14),
        ],
        if (title != null)
          DefaultTextStyle.merge(
            style: TextStyle(
              color: AppColors.onScaffold(context),
              fontSize: 17,
              height: 1.25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
            child: title!,
          ),
        if (title != null && content != null) const SizedBox(height: 8),
        if (content != null)
          DefaultTextStyle.merge(
            style: TextStyle(
              color: AppColors.mutedText(context),
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
            child: content!,
          ),
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Theme(
            data: _actionsTheme(context),
            child: Padding(
              padding: actionsPadding ?? EdgeInsets.zero,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: actions!,
              ),
            ),
          ),
        ],
      ],
    );
    final padded = Padding(
      padding: contentPadding ?? const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: body,
    );

    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(
            width: double.infinity,
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              namesRoute: title != null,
              // 对话框不在页面里，没有 Material 祖先时 Text 会退回
              // DefaultTextStyle.fallback（丢掉主题字体，中文直接变方块）。
              child: Material(
                type: MaterialType.transparency,
                child: GlassSurface(
                  // iOS modal material: the page remains visible through the
                  // blur; the edge, not a heavy drop shadow, defines the panel.
                  style: AppGlassStyle.sheet,
                  borderRadius: BorderRadius.circular(radius),
                  emphasized: true,
                  color: backgroundColor,
                  border: Border.all(
                    color: AppGlass.hairline(context, emphasized: true).color,
                    width: 0.7,
                  ),
                  boxShadow: const <BoxShadow>[],
                  child: scrollable
                      ? ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: maxHeight - 48,
                          ),
                          child: SingleChildScrollView(child: padded),
                        )
                      : ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: maxHeight - 48,
                          ),
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: padded,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Dialog actions sit on a smaller type scale than page buttons and use a
  /// pill radius, so the same `TextButton`/`FilledButton` call sites read as
  /// iOS-style actions without being rewritten one by one.
  ThemeData _actionsTheme(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const size = Size(64, 38);
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 9);
    // 必须从主题的 label 样式派生：裸 TextStyle 没有 fontFamily，
    // 中文会掉进引擎兜底字体（渲染成方块）。
    final label = theme.textTheme.labelLarge ?? const TextStyle();
    return theme.copyWith(
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondaryText(context),
          minimumSize: size,
          padding: padding,
          textStyle: label.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: size,
          padding: padding,
          elevation: 0,
          textStyle: label.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onScaffold(context),
          minimumSize: size,
          padding: padding,
          side: BorderSide(color: AppColors.cardBorder(context)),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }

  static double _radius(ShapeBorder? shape) {
    if (shape is RoundedRectangleBorder) {
      final borderRadius = shape.borderRadius;
      if (borderRadius is BorderRadius) return borderRadius.topLeft.x;
    }
    return 26;
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(
          alpha: AppColors.isDark(context) ? 0.16 : 0.11,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: accent, size: 22),
        child: icon,
      ),
    );
  }
}
