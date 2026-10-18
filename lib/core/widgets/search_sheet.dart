import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:koyze/features/search/presentation/search_screen.dart';

import '../motion/motion_tokens.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// 弹出 Origo 风格搜索浮层。
///
/// 这里不再借用系统底部弹层的拖拽：那条路径会把系统弹层自己的位移动画
/// 和页面里的手工位移叠加在一起，手势起来像「旧版弹层」。
/// 改成自绘 [PopupRoute]，由一条进度同时驱动：
/// 位移、缩放、遮罩浓度、内容淡入和关闭，拖动与回弹共用同一套几何。
Future<void> showSearchSheet(BuildContext context, {required double topInset}) {
  final media = MediaQuery.of(context);
  final size = media.size;
  final landscape = size.width > size.height;
  final desktop = size.width >= 1100;
  // 搜索面板只占主要工作区，顶部明确留出首页上下文；结果继续滚动，
  // 不用靠一块接近全屏的空玻璃来撑高度。
  final ratio = desktop
      ? 0.68
      : landscape
      ? 0.94
      : 0.78;
  // 横屏和桌面已经有足够的顶部上下文，不再把首页标题位置当作
  // 面板高度的扣除项；手机仍按标题位置留出明显的上下文。
  final topClearance = landscape ? 8.0 : topInset;
  var height = min(size.height - topClearance, size.height * ratio);
  // 桌面按内容密度收敛到一张工作面板，不让结果贴在上方、空白拖到底部。
  if (desktop) height = min(height, 430);
  // 宽度按设备收窄：搜索面板不需要桌面级的宽度，720 已经足够放下
  // 两列结果，再宽只会让每行拉得太空。
  final maxWidth = size.width >= 1100
      ? 720.0
      : landscape
      ? 640.0
      : 560.0;

  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<void>(
    _SearchSheetRoute(
      height: height,
      maxWidth: maxWidth,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

class _SearchSheetRoute extends PopupRoute<void> {
  _SearchSheetRoute({
    required this.height,
    required this.maxWidth,
    required this.barrierLabel,
    required this.themes,
  });

  final double height;
  final double maxWidth;
  final CapturedThemes themes;

  @override
  final String barrierLabel;
  @override
  bool get barrierDismissible => true;

  // 遮罩由面板自己按进度绘制，这样拖动时底层能跟着变亮，
  // 而不是等到关闭动画开始才整体淡出。
  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => effectsDuration(MotionDuration.sheet);

  @override
  Duration get reverseTransitionDuration =>
      effectsDuration(MotionDuration.sheetReverse);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: _SearchSheetPanel(
            height: height,
            maxWidth: maxWidth,
            animation: animation,
          ),
        ),
      ),
    );
  }
}

class _SearchSheetPanel extends StatefulWidget {
  const _SearchSheetPanel({
    required this.height,
    required this.maxWidth,
    required this.animation,
  });

  final double height;
  final double maxWidth;
  final Animation<double> animation;

  @override
  State<_SearchSheetPanel> createState() => _SearchSheetPanelState();
}

class _SearchSheetPanelState extends State<_SearchSheetPanel>
    with SingleTickerProviderStateMixin {
  static const double _sideGap = 16;
  static const double _bottomGap = 12;
  static const double _handleHeight = 14;

  /// 0 = 完全展开，1 = 完全拖出屏幕。拖动、回弹和关闭动画都只改这一个值。
  double _extent = 0;
  bool _draggingFromScroll = false;
  bool _dismissing = false;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: MotionDuration.normal,
  );
  double _settleFrom = 0;
  double _settleTo = 0;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// 当前展示的进度：跟随手指，或正在按 Origο 的减速曲线回弹。
  double get _drag {
    if (!_settle.isAnimating) return _extent;
    final t = MotionCurve.iosSpring.transform(_settle.value.clamp(0.0, 1.0));
    return _settleFrom + (_settleTo - _settleFrom) * t;
  }

  bool get _portrait {
    final size = MediaQuery.sizeOf(context);
    return size.height > size.width;
  }

  /// 竖屏弹键盘时面板要整体上移并收短；横屏高度本来就紧，
  /// 仍由列表自己补底部留白。
  double get _panelHeight {
    final keyboard = _portrait ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    return max(160.0, widget.height - keyboard);
  }

  double get _bottomInset {
    final safe = MediaQuery.paddingOf(context).bottom;
    return max(_bottomGap, safe + 4);
  }

  /// 面板完全离开屏幕所需的位移，用于把像素增量折算成进度。
  double get _travel => _panelHeight + _bottomInset;

  void _beginDrag() {
    if (_dismissing) return;
    if (_settle.isAnimating) {
      // 从回弹中途重新接管：先把当前视觉位置固化下来，避免跳变。
      final current = _drag;
      _settle.stop();
      _extent = current;
      setState(() {});
    }
  }

  void _dragBy(double dy) {
    if (_dismissing || dy == 0) return;
    final current = _drag;
    if (_settle.isAnimating) _settle.stop();
    final travel = _travel;
    if (travel <= 0) return;
    final next = (current + dy / travel).clamp(0.0, 1.0);
    if ((next - current).abs() < 1e-4) {
      if (_settle.isAnimating) setState(() => _extent = next);
      return;
    }
    setState(() => _extent = next);
  }

  void _endDrag(double velocity) {
    if (_dismissing) return;
    _draggingFromScroll = false;
    final travel = _travel;
    if (travel <= 0) return;
    // 用 160ms 的速度投影判断去向：轻甩也能直接关掉，
    // 慢速拖到一半以上同样关闭，剩下的都弹回原位。
    final projected = _extent + velocity / travel * 0.16;
    if (velocity > 850 || projected >= 0.42) {
      unawaited(_dismiss());
      return;
    }
    if (_extent <= 0.001) {
      setState(() => _extent = 0);
      return;
    }
    unawaited(_settleBack());
  }

  Future<void> _settleBack() async {
    _settleFrom = _drag;
    _settleTo = 0;
    _settle.duration = motionDuration(context, MotionDuration.normal);
    await _settle.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _extent = 0;
      _settle.reset();
    });
  }

  /// 关闭交给路由的反向动画：进度从当前 `_extent` 接着往 1 走，
  /// 不会出现「先弹回原位再整体淡出」的二次位移。
  Future<void> _dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    if (_settle.isAnimating) _settle.stop();
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    unawaited(Navigator.of(context).maybePop());
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (_dismissing) return false;
    if (notification is OverscrollNotification) {
      final dy = notification.dragDetails?.delta.dy;
      if (dy != null && dy > 0) {
        _draggingFromScroll = true;
        _dragBy(dy);
        return true;
      }
    } else if (notification is ScrollUpdateNotification) {
      // iOS 的 Bouncing 物理不会发 Overscroll，越界滚动走 ScrollUpdate。
      final dy = notification.dragDetails?.delta.dy;
      if (dy == null) return false;
      final metrics = notification.metrics;
      final atTop = metrics.pixels <= metrics.minScrollExtent + 0.5;
      if (atTop && (dy > 0 || _extent > 0)) {
        _draggingFromScroll = true;
        _dragBy(dy);
        return true;
      }
    } else if (notification is ScrollEndNotification && _draggingFromScroll) {
      _draggingFromScroll = false;
      _endDrag(notification.dragDetails?.primaryVelocity ?? 0);
      return false;
    }
    return false;
  }

  double get _scrimAlpha =>
      AppColors.isDark(context) ? 0.54 : 0.30;

  @override
  Widget build(BuildContext context) {
    final keyboard = _portrait ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    final panelHeight = _panelHeight;
    final bottomInset = _bottomInset;
    final travel = panelHeight + bottomInset;
    return AnimatedBuilder(
      animation: Listenable.merge([widget.animation, _settle]),
      builder: (context, _) {
        final enter = reduceMotion(context)
            ? 1.0
            : widget.animation.value.clamp(0.0, 1.0);
        final drag = _drag.clamp(0.0, 1.0);
        // Origo 的几何变形统一走强调曲线：起步稳、落位干脆。
        final progress = Curves.easeInOutCubicEmphasized.transform(enter);
        // 进场：从屏幕下方推到位置；拖动：在当前进度上继续往下走。
        final dy = (1 - progress) * travel + drag * travel;
        // 面板被按住下拖时轻微缩小并淡出，像从页面里被「揭」下来。
        final scale = (0.94 + 0.06 * progress) * (1 - 0.08 * drag);
        final reveal = const Interval(
          0.16,
          0.72,
          curve: Curves.easeOut,
        ).transform(enter);
        final scrim = _scrimAlpha * progress * (1 - drag);
        final opacity = (reveal * (1 - 0.45 * drag)).clamp(0.0, 1.0);

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: scrim),
                ),
              ),
            ),
            Positioned(
              left: _sideGap,
              right: _sideGap,
              bottom: keyboard + bottomInset,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: widget.maxWidth),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: panelHeight,
                        child: Opacity(
                          opacity: opacity,
                          child: IgnorePointer(
                            ignoring: reveal < 1,
                            child: _panel(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _panel(BuildContext context) {
    final dark = AppColors.isDark(context);
    const radius = 28.0;
    // 自绘路由不再自带 Material，输入框和 InkWell 需要一个透明的材质祖先。
    return Material(
      type: MaterialType.transparency,
      child: GlassSurface(
        style: AppGlassStyle.regular,
        borderRadius: BorderRadius.circular(radius),
        emphasized: true,
        // 浅色面板降低基底不透明度，保留首页的色块层次而不是整块发白；
        // 深色保持更高对比，让结果行和面板边界稳定。
        vivid: false,
        alphaScale: dark ? 0.92 : 1.0,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.48 : 0.16),
            blurRadius: 30,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
        ],
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: SearchScreen(
                  embedded: true,
                  liveSearch: true,
                  reserveKeyboardInset: false,
                  onDismiss: _dismiss,
                  autofocusDelay: _focusDelay(),
                  canAutofocus: () => !_dismissing,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _handleHeight,
                child: _dragHandle(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部细抓条既是拖拽把手，也给「这块可以往下拽」一个可看见的暗示。
  Widget _dragHandle(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('search-sheet-drag-handle'),
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) => _beginDrag(),
      onVerticalDragUpdate: (details) => _dragBy(details.delta.dy),
      onVerticalDragEnd: (details) => _endDrag(details.primaryVelocity ?? 0),
      onVerticalDragCancel: () => _endDrag(0),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: 34,
          height: 4,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: AppColors.mutedText(context).withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }

  /// 等待路由进场动画结束后再交给输入框聚焦，避免焦点在转场期间
  /// 被底层页面重新夺回，导致键盘刚弹出就关闭。
  Duration _focusDelay() => const Duration(milliseconds: 650);
}
