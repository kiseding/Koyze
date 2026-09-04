import 'package:flutter/material.dart';
import '../motion/motion_tokens.dart';
import '../theme/app_tokens.dart';

/// 统一的底部弹窗：从底部进入 + 轻微淡入/缩放 + scrim 平滑出现。
/// 所有 showModalBottomSheet 调用点统一替换，保证 Modal Motion 一致。
///
/// 默认铺磨砂玻璃。调用方若自己包了 [GlassSurface]（或需要完全透明），
/// 传 [backgroundColor] = [Colors.transparent] 并设 [frosted] = false。
Future<T?> showKoyzeSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  bool enableDrag = true,
  bool frosted = true,
}) {
  final useGlass = frosted && backgroundColor != Colors.transparent;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    requestFocus: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    sheetAnimationStyle: AnimationStyle(
      duration: MotionDuration.normal,
      reverseDuration: MotionDuration.micro,
      curve: MotionCurve.easeOut,
      reverseCurve: MotionCurve.easeIn,
    ),
    builder: (context) {
      final content = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MotionDuration.normal,
        curve: MotionCurve.easeOut,
        builder: (context, t, child) => Transform.scale(
          scale: 1 - 0.02 * (1 - t),
          child: Opacity(opacity: t, child: child),
        ),
        child: builder(context),
      );
      if (!useGlass) return content;
      return GlassSurface(
        style: AppGlassStyle.regular,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        color: backgroundColor,
        child: content,
      );
    },
  );
}
