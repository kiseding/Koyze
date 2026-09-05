import 'package:flutter/material.dart';
import '../motion/motion_tokens.dart';

/// 统一的底部弹窗：从底部进入 + 轻微淡入/缩放 + scrim 平滑出现。
/// 所有 showModalBottomSheet 调用点统一替换，保证 Modal Motion 一致。
Future<T?> showKoyzeSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    requestFocus: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    sheetAnimationStyle: const AnimationStyle(
      duration: MotionDuration.normal,
      reverseDuration: MotionDuration.micro,
      curve: MotionCurve.easeOut,
      reverseCurve: MotionCurve.easeIn,
    ),
    builder: (context) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MotionDuration.normal,
        curve: MotionCurve.easeOut,
        builder: (context, t, child) => Transform.scale(
          scale: 1 - 0.02 * (1 - t),
          child: Opacity(opacity: t, child: child),
        ),
        child: builder(context),
      );
    },
  );
}
