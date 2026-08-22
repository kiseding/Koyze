import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:koyze/features/search/presentation/search_screen.dart';

import '../motion/motion_tokens.dart';

/// 弹出搜索弹窗。
/// 弹窗从底部滑入，顶部对齐传入的 [topInset]（首页 Koyze 文字上方 3px）；
/// 顶部小白条可按住上下拖动；列表滑到顶后继续下拉时弹窗跟随下滑，
/// 超过阈值关闭；滑入后自动聚焦输入框弹出键盘。
Future<void> showSearchSheet(BuildContext context, {required double topInset}) {
  final size = MediaQuery.sizeOf(context);
  final height = max(size.height - topInset, 200.0);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black45,
    sheetAnimationStyle: AnimationStyle(
      duration: MotionDuration.container,
      reverseDuration: MotionDuration.micro,
      curve: MotionCurve.easeOut,
      reverseCurve: MotionCurve.easeIn,
    ),
    builder: (context) => _SearchSheet(height: height),
  );
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.height});

  final double height;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _draggingFromScroll = false;
  bool _settling = false;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: MotionDuration.normal,
  );
  double _settleFrom = 0;
  double _settleTo = 0;

  double get _closeThreshold => widget.height * 0.22;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// 当前展示的位移（跟随手势或回弹动画）。
  double get _offset => _settle.isAnimating
      ? _settleFrom +
            (_settleTo - _settleFrom) *
                Curves.easeOutCubic.transform(_settle.value)
      : _dragOffset;

  void _startSettle(double from, double to) {
    _settleFrom = from;
    _settleTo = to;
    _settle.forward(from: 0);
  }

  void _applyDragDelta(double dy) {
    if (dy == 0) return;
    _dragOffset = max(0, _dragOffset + dy);
    if (_settle.isAnimating) _settle.stop();
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _applyDragDelta(details.delta.dy);
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    await _finishDrag(details.primaryVelocity ?? 0);
  }

  Future<void> _finishDrag(double velocity) async {
    if (_settling) return;
    _draggingFromScroll = false;
    if (_dragOffset > _closeThreshold || velocity > 700) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }
    if (_dragOffset > 0) {
      _settling = true;
      _startSettle(_dragOffset, 0);
      await _settle.forward(from: 0);
      if (mounted) {
        setState(() {
          _dragOffset = 0;
          _settling = false;
        });
      }
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // 列表已在顶部时继续下拉：弹窗跟手；已有位移时继续接管手势。
    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      final delta = notification.dragDetails?.delta.dy;
      if (delta == null) return false;
      final atTop = metrics.pixels <= metrics.minScrollExtent + 0.5;
      if (_dragOffset > 0 || (atTop && delta > 0)) {
        _draggingFromScroll = true;
        _applyDragDelta(delta);
        return true;
      }
    } else if (notification is OverscrollNotification) {
      final dy = notification.dragDetails?.delta.dy;
      if (dy != null && dy > 0) {
        _draggingFromScroll = true;
        _applyDragDelta(dy);
        return true;
      }
    } else if (notification is ScrollEndNotification && _draggingFromScroll) {
      final velocity = notification.dragDetails?.primaryVelocity ?? 0;
      unawaited(_finishDrag(velocity));
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settle,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _offset), child: child),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) {
                  if (_settle.isAnimating) _settle.stop();
                },
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                child: Container(
                  width: double.infinity,
                  height: 28,
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Expanded(child: SearchScreen(autofocusDelay: _focusDelay())),
            ],
          ),
        ),
      ),
    );
  }

  /// 等待 ModalBottomSheet 完成进入动画后再交给输入框聚焦，避免焦点
  /// 在路由动画期间被底层页面重新夺回，导致键盘刚弹出就关闭。
  Duration _focusDelay() => const Duration(milliseconds: 650);
}
