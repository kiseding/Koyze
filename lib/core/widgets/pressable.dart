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
          : (_) {
              setState(() {
                _pressed = false;
                _releasing = true;
              });
              if (!widget.captureExpandRect) {
                _releasing = false;
                onActivate.call();
                return;
              }
              // 先把几何和快照塞进 capture 的同步段、立刻起跑路由，
              // 再在后台等 GPU 回读完成。
              //
              // 旧实现在这里 `await Future.wait([capture, 105ms])`，
              // 等于每次点卡片都先干等 105ms 才 push：屏幕上按下去之后
              // 有 5~6 帧完全静止，然后整屏硬切——用户看到的"不流畅"。
              // 105ms 本来是想让按压回弹先播完，但路由动画的 300ms 里
              // 已经包含这段，多等一次只是把它变成空窗。
              //
              // `captureCardExpandOrigin` 的矩形记录是同步完成的（第一行
              // 就写 `_cardExpandRect`），所以哪怕不 await 它也一定能被
              // 随后的 pageBuilder 吃到——矩形 morph 不会退化。
              // 快照要等 GPU 回读，晚到的那几帧只是没有快照可用
              // （`sourceSnapshot == null`，转场走纯几何路径），
              // 不会阻塞导航，也不会让动画停住。
              final anchor = _expandAnchorKey.currentContext;
              final pending = anchor == null
                  ? Future<void>.value()
                  : captureCardExpandOrigin(anchor);
              _releasing = false;
              onActivate.call();
              // 需要挂一个兜底，否则 GPU 回读失败时未处理的异步异常
              // 会冒到 zone 外。它必须在 call 之后——放在前面就是死等。
              pending.catchError((Object _) {});
            },
      onTapCancel: onActivate == null ? null : () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: motionDuration(
          context,
          _releasing ? const Duration(milliseconds: 240) : widget.duration,
        ),
        curve: _releasing ? Curves.easeOutBack : MotionCurve.easeOutQuart,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.92 : 1,
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

    final visibleChild = widget.captureExpandRect
        ? ValueListenableBuilder<bool>(
            valueListenable: cardExpandSourceHidden,
            builder: (context, hidden, child) => Opacity(
              opacity:
                  hidden && identical(_expandAnchorKey, cardExpandHiddenKey)
                  ? 0
                  : 1,
              child: child,
            ),
            child: anchoredChild,
          )
        : anchoredChild;

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
        child: ExcludeSemantics(child: visibleChild),
      ),
    );
  }
}
