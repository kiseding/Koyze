import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion_tokens.dart';

/// Compact play button with immediate, visible feedback for content cards.
class CardPlayButton extends StatefulWidget {
  const CardPlayButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.color,
    required this.backgroundColor,
    this.tooltip = '播放全部',
    this.size = 48,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final Color color;
  final Color backgroundColor;
  final String tooltip;
  final double size;

  @override
  State<CardPlayButton> createState() => _CardPlayButtonState();
}

class _CardPlayButtonState extends State<CardPlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounce;
  final FocusNode _focusNode = FocusNode();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MotionDuration.container,
    );
    _bounce = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 1, end: 0.78), weight: 22),
        TweenSequenceItem(tween: Tween(begin: 0.78, end: 1.16), weight: 38),
        TweenSequenceItem(tween: Tween(begin: 1.16, end: 1), weight: 40),
      ],
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  void _activate() {
    final callback = widget.onPressed;
    if (callback == null) return;
    HapticFeedback.selectionClick();
    if (!reduceMotion(context)) _controller.forward(from: 0);
    callback();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                _activate();
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final progress = Curves.easeOutCubic.transform(_controller.value);
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Opacity(
                    key: const ValueKey('card-play-feedback-ring'),
                    opacity: enabled && _controller.isAnimating
                        ? (1 - progress) * 0.55
                        : 0,
                    child: Transform.scale(
                      scale: 0.8 + progress * 0.75,
                      child: Container(
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: widget.color, width: 3),
                        ),
                      ),
                    ),
                  ),
                  AnimatedScale(
                    key: const ValueKey('card-play-feedback-button'),
                    scale: _pressed ? 0.78 : _bounce.value,
                    duration: _pressed ? MotionDuration.micro : Duration.zero,
                    curve: Curves.easeOutCubic,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        color: widget.backgroundColor,
                        shape: BoxShape.circle,
                        boxShadow: _controller.isAnimating
                            ? [
                                BoxShadow(
                                  color: widget.color.withValues(
                                    alpha: 0.38 * (1 - progress),
                                  ),
                                  blurRadius: 16 + progress * 8,
                                  spreadRadius: 2 + progress * 4,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(child: widget.icon),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    return FocusableActionDetector(
      focusNode: _focusNode,
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        onTap: enabled ? _activate : null,
        child: ExcludeSemantics(
          child: Tooltip(message: widget.tooltip, child: button),
        ),
      ),
    );
  }
}
