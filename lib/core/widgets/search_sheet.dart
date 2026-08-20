import 'dart:math';

import 'package:flutter/material.dart';
import 'package:koyze/features/search/presentation/search_screen.dart';

/// 弹出搜索弹窗。
/// 弹窗从底部滑入，顶部对齐传入的 [topInset]（首页 Koyze 文字上方 3px）；
/// 顶部小白条可按住上下拖动（内容跟随手指），下拉超过阈值关闭，
/// 否则回弹；滑入超过 2/3 时聚焦输入框弹出键盘。
Future<void> showSearchSheet(BuildContext context, {required double topInset}) {
  final size = MediaQuery.sizeOf(context);
  final height = max(size.height - topInset, 200.0);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black45,
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

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  double _settleFrom = 0;
  double _settleTo = 0;

  double get _closeThreshold => widget.height * 0.25;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// 当前展示的位移（跟随手势或回弹动画）。
  double get _offset => _settle.isAnimating
      ? _settleFrom + (_settleTo - _settleFrom) * _settle.value
      : _dragOffset;

  void _startSettle(double from, double to) {
    _settleFrom = from;
    _settleTo = to;
    _settle.forward(from: 0);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragOffset = max(0, _dragOffset + details.delta.dy);
    if (_settle.isAnimating) _settle.stop();
    setState(() {});
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > _closeThreshold || velocity > 800) {
      // 整个弹窗（含背景）已随手指下移，直接 pop 由默认动画收尾。
      Navigator.pop(context);
      return;
    }
    if (_dragOffset > 0) {
      _startSettle(_dragOffset, 0);
      await _settle.forward(from: 0);
      if (mounted) setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 整个弹窗（含背景）一起位移：拖动手感跟手，且不会在原位置留白。
    return AnimatedBuilder(
      animation: _settle,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _offset), child: child),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // 顶部小白条：按住上下拖动，内容跟随手指。
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
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    // 纯色不透明：浅色主题深灰，深色主题白。
                    color: Theme.of(context).colorScheme.onSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // 搜索内容（无返回按钮，弹窗下拉即可关闭）。
            Expanded(child: SearchScreen(autofocusDelay: _focusDelay())),
          ],
        ),
      ),
    );
  }

  /// 弹窗滑入动画约 400ms，超过 2/3 时聚焦（≈267ms）。
  Duration _focusDelay() => const Duration(milliseconds: 270);
}
