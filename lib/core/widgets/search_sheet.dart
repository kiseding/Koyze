import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:koyze/features/search/presentation/search_screen.dart';

import '../motion/motion_tokens.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// 弹出 Origo 风格搜索弹窗。
/// 面板从底部滑入并保留页面上下文；系统 bottom sheet 负责顶部拖拽，
/// 列表滑到顶后继续下拉时弹窗也会跟随下滑，超过阈值关闭；
/// 滑入后自动聚焦输入框弹出键盘。
Future<void> showSearchSheet(BuildContext context, {required double topInset}) {
  final size = MediaQuery.sizeOf(context);
  final landscape = size.width > size.height;
  // 搜索面板只占主要工作区，顶部明确留出首页上下文；结果继续滚动，
  // 不用靠一块接近全屏的空玻璃来撑高度。
  final desktop = size.width >= 1100;
  final ratio = desktop
      ? 0.68
      : landscape
      ? 0.94
      : 0.78;
  // 横屏和桌面已经有足够的顶部上下文，不再把首页标题位置当作
  // sheet 高度的扣除项；手机仍按标题位置留出明显的上下文。
  final topClearance = landscape ? 8.0 : topInset;
  var height = min(size.height - topClearance, size.height * ratio);
  // 桌面按内容密度收敛到一张工作面板，不让结果贴在上方、空白拖到底部。
  if (desktop) height = min(height, 430);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    showDragHandle: false,
    useSafeArea: true,
    requestFocus: false,
    backgroundColor: Colors.transparent,
    // 宽度按设备收窄：搜索面板不需要桌面级的宽度，720 已经足够放下
    // 两列结果，再宽只会让每行拉得太空。
    constraints: BoxConstraints(
      maxWidth: size.width >= 1100
          ? 720
          : landscape
          ? 640
          : 560,
    ),
    // 遮罩需要把底层降到上下文级别，面板本身再用玻璃保留一点颜色。
    barrierColor: Colors.black.withValues(
      alpha: AppColors.isDark(context) ? 0.54 : 0.30,
    ),
    sheetAnimationStyle: effectsAnimationStyle(
      duration: MotionDuration.sheet,
      reverseDuration: Duration.zero,
      curve: MotionCurve.sheetIn,
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
  bool _dismissStarted = false;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: MotionDuration.normal,
  );
  double _settleFrom = 0;
  double _settleTo = 0;

  double get _closeThreshold => widget.height * 0.22;

  /// 面板底边与屏幕底之间保留的缝，配合四角圆角让它像一块浮起来的卡片。
  static const double _bottomGap = 12;

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

  Future<void> _animateSettle(double from, double to, Duration duration) {
    _settleFrom = from;
    _settleTo = to;
    _settle.duration = motionDuration(context, duration);
    return _settle.forward(from: 0);
  }

  void _applyDragDelta(double dy) {
    if (_dismissStarted) return;
    if (dy == 0) return;
    _dragOffset = max(0, _dragOffset + dy);
    if (_settle.isAnimating) _settle.stop();
    setState(() {});
    if (_dragOffset > _closeThreshold) {
      unawaited(_dismissSheet());
    }
  }

  Future<void> _finishDrag(double velocity) async {
    if (_settling || _dismissStarted) return;
    _draggingFromScroll = false;
    if (velocity > 700) {
      await _dismissSheet();
      return;
    }
    if (_dragOffset > 0) {
      _settling = true;
      await _animateSettle(_dragOffset, 0, MotionDuration.normal);
      if (mounted) {
        setState(() {
          _dragOffset = 0;
          _settling = false;
        });
      }
    }
  }

  Future<void> _dismissSheet() async {
    if (_dismissStarted || !mounted) return;
    _dismissStarted = true;
    FocusManager.instance.primaryFocus?.unfocus();
    _settling = true;
    await _animateSettle(_dragOffset, widget.height, MotionDuration.micro);
    _dragOffset = widget.height;
    if (!mounted) return;
    Navigator.pop(context);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (_dismissStarted) return true;
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
    final media = MediaQuery.of(context);
    // 所有宽度档都留出侧边：即使面板本身已经被 maxWidth 收窄，
    // 也不能让中等横屏窗口出现整块贴边的玻璃面板。
    const side = 16.0;
    // 竖屏时让面板底边停在键盘上沿：否则面板底部三分之一藏在输入法后面，
    // 看起来像被裁掉。注意要在「顶边固定」的前提下缩高度——直接缩
    // SizedBox 会让底边贴着屏幕底、顶边反而往下掉。
    // 横屏本来就矮，再缩会把结果区挤没，改为由列表自己补底部留白。
    final keyboard = media.size.height > media.size.width
        ? media.viewInsets.bottom
        : 0.0;
    return AnimatedBuilder(
      animation: _settle,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _offset), child: child),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: SizedBox(
          height: widget.height,
          child: AnimatedPadding(
            duration: motionDuration(context, MotionDuration.micro),
            curve: MotionCurve.easeOutQuart,
            // 面板四边都离开屏幕边缘：底边常留 12pt，弹键盘时再让出键盘高度。
            // 不再贴屏幕底，所以四角统一收圆，不会在键盘上方露出直角。
            padding: EdgeInsets.fromLTRB(side, 0, side, keyboard + _bottomGap),
            child: GlassSurface(
              style: AppGlassStyle.regular,
              borderRadius: BorderRadius.circular(28),
              emphasized: true,
              // 浅色面板降低基底不透明度，保留首页的色块层次而不是整块发白；
              // 深色保持更高对比，让结果行和面板边界稳定。
              vivid: false,
              alphaScale: AppColors.isDark(context) ? 0.92 : 1.0,
              boxShadow: [
                BoxShadow(
                  color: AppColors.isDark(context)
                      ? Colors.black.withValues(alpha: 0.48)
                      : Colors.black.withValues(alpha: 0.16),
                  blurRadius: 30,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
                ),
              ],
              child: SearchScreen(
                embedded: true,
                liveSearch: true,
                reserveKeyboardInset: false,
                onDismiss: _dismissSheet,
                autofocusDelay: _focusDelay(),
                canAutofocus: () => !_dismissStarted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 等待 ModalBottomSheet 完成进入动画后再交给输入框聚焦，避免焦点
  /// 在路由动画期间被底层页面重新夺回，导致键盘刚弹出就关闭。
  Duration _focusDelay() => const Duration(milliseconds: 650);
}
