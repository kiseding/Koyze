import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';

/// 图标/状态切换动效：150ms 淡入 + 0.9→1 微缩放。
/// 全项目图标切换统一使用，保证同一类型元素动效一致。
class AnimatedIconSwitch extends StatelessWidget {
  const AnimatedIconSwitch({
    super.key,
    required this.icon,
    required this.keyValue,
    this.color,
    this.size,
    this.duration = const Duration(milliseconds: 150),
  });

  final IconData icon;
  final Object keyValue;
  final Color? color;
  final double? size;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motionDuration(context, duration),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Icon(icon, key: ValueKey(keyValue), color: color, size: size),
    );
  }
}

/// 数字变化滚动动效：250ms easeOutCubic 从旧值滚动到新值。
/// 高频刷新（如播放时间）不要使用。
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 250),
  });

  final int value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: motionDuration(context, duration),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$v', style: style),
    );
  }
}

/// 桌面端 hover 上浮动效：悬停时上移 2px 并加深阴影，200ms。
/// 仅用于渐变大卡片等视觉重点元素。
class HoverFloat extends StatefulWidget {
  const HoverFloat({
    super.key,
    required this.child,
    this.offsetY = -2,
    this.duration = const Duration(milliseconds: 200),
  });

  final Widget child;
  final double offsetY;
  final Duration duration;

  @override
  State<HoverFloat> createState() => _HoverFloatState();
}

class _HoverFloatState extends State<HoverFloat> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final animationsDisabled = reduceMotion(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedSlide(
        offset: _hovered && !animationsDisabled
            ? Offset(0, widget.offsetY / 100)
            : Offset.zero,
        duration: motionDuration(context, widget.duration),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
