import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../card_expand.dart';
import '../motion/motion_tokens.dart';

/// 按下缩放动效包装器，用于主要可点击控件。
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Duration duration;
  final BorderRadius? borderRadius;
  final String? semanticLabel;
  final bool? selected;
  final String? tooltip;
  final bool captureExpandRect;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.92,
    this.duration = const Duration(milliseconds: 110),
    this.borderRadius,
    this.semanticLabel,
    this.selected,
    this.tooltip,
    this.captureExpandRect = false,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;
  bool _releasing = false;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _expandAnchorKey = GlobalKey();

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onActivate = widget.onTap;
    final interactiveChild = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onActivate == null
          ? null
          : (_) {
              _focusNode.requestFocus();
              _setPressed(true);
            },
      onTapUp: onActivate == null
          ? null
          : (_) async {
              setState(() {
                _pressed = false;
                _releasing = true;
              });
              if (widget.captureExpandRect) {
                final anchor = _expandAnchorKey.currentContext;
                await Future.wait<void>([
                  if (anchor != null) captureCardExpandOrigin(anchor),
                  Future<void>.delayed(const Duration(milliseconds: 105)),
                ]);
                if (!mounted) return;
              }
              _releasing = false;
              onActivate.call();
            },
      onTapCancel: onActivate == null ? null : () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: motionDuration(
          context,
          _releasing ? const Duration(milliseconds: 210) : widget.duration,
        ),
        curve: _releasing ? Curves.easeOutBack : Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.88 : 1,
          duration: motionDuration(context, widget.duration),
          child: widget.borderRadius == null
              ? widget.child
              : ClipRRect(
                  borderRadius: widget.borderRadius!,
                  child: widget.child,
                ),
        ),
      ),
    );

    final anchoredChild = widget.captureExpandRect
        ? RepaintBoundary(key: _expandAnchorKey, child: interactiveChild)
        : interactiveChild;

    return Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: onActivate != null,
      selected: widget.selected,
      tooltip: widget.tooltip,
      onTap: onActivate,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        enabled: onActivate != null,
        mouseCursor: onActivate == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onActivate?.call();
              return null;
            },
          ),
        },
        child: ExcludeSemantics(child: anchoredChild),
      ),
    );
  }
}
