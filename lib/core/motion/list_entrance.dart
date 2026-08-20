import 'package:flutter/material.dart';
import '../../core/motion/motion_tokens.dart';

/// 列表项首次挂载时的轻量入场：淡入 + 上移 8px，180ms。
/// 复用 element 时不重播（ListView 回收安全），滚动时不会闪烁。
class ListEntrance extends StatelessWidget {
  const ListEntrance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motionDuration(context, MotionDuration.micro * 1.2),
      curve: MotionCurve.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, MotionDistance.subtle * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
