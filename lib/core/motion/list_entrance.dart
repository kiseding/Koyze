import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/motion/motion_tokens.dart';

/// 列表项首次挂载时的轻量入场：淡入 + 上移 10px。
///
/// 传入 [index] 时按行错峰（每行 +32ms，最多 6 行），一屏卡片会依次浮上来
/// 而不是整体一起出现；不传则所有项同时入场。
/// 复用 element 时不重播（ListView 回收安全），滚动时不会闪烁。
class ListEntrance extends StatelessWidget {
  const ListEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.maxDelaySteps = 6,
  });

  final Widget child;
  final int index;
  final int maxDelaySteps;

  static const Duration _base = Duration(milliseconds: 220);
  static const double _staggerMs = 32;

  @override
  Widget build(BuildContext context) {
    final delay = min(index, maxDelaySteps) * _staggerMs;
    final total = _base.inMilliseconds + delay;
    final start = delay / total;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motionDuration(context, Duration(milliseconds: total.round())),
      curve: Interval(start, 1, curve: MotionCurve.easeOutQuart),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
