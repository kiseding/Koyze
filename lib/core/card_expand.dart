import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'motion/motion_tokens.dart';

/// 卡片"长成"全屏页的展开转场。
///
/// 点击卡片时先调用 [captureCardExpandRect] 记录卡片的屏幕矩形，
/// 再 push 二级页；路由的 pageBuilder 通过 [consumeCardExpandRect]
/// 一次性消费该矩形，transitionsBuilder 据此做「从卡片矩形缩放展开 +
/// 圆角收敛」的过渡（与全屏播放器的矩形 morph 同机制）。
/// 其他入口进入（未记录矩形）时退化为默认的上滑淡入。
Rect? _cardExpandRect;
ui.Image? _cardExpandSnapshot;

/// 记录当前卡片的屏幕矩形（供展开转场使用）。
void captureCardExpandRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize && box.attached) {
    _cardExpandRect = box.localToGlobal(Offset.zero) & box.size;
  }
}

/// 同时记录卡片几何和像素快照。快照只在转场前短暂保留，用于让源卡片
/// 本体先随边界长大，再交给目标页面内容。
Future<void> captureCardExpandOrigin(BuildContext context) async {
  captureCardExpandRect(context);
  final boundary = context.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null || !boundary.attached || !boundary.hasSize) return;
  try {
    // 按设备像素密度截图（封顶 2x），否则收拢成卡片后快照被插值放大、
    // 文字发虚。
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final snapshot = await boundary.toImage(
      pixelRatio: dpr.clamp(1.0, 2.0),
    );
    _cardExpandSnapshot?.dispose();
    _cardExpandSnapshot = snapshot;
  } catch (_) {
    // GPU 快照偶发失败时仍使用几何转场，不能阻断导航。
  }
}

/// 消费并清空展开矩形；pageBuilder 中调用一次。
Rect? consumeCardExpandRect() {
  final rect = _cardExpandRect;
  _cardExpandRect = null;
  return rect;
}

ui.Image? consumeCardExpandSnapshot() {
  final snapshot = _cardExpandSnapshot;
  _cardExpandSnapshot = null;
  return snapshot;
}

/// 卡片拖拽关闭进度（0..1，1 = 完全收起成卡片）。
/// EdgeSwipeDismiss 拖动时实时写入，_CardRevealTransition 据此让
/// 矩形 morph 跟手收拢，松开后从当前位置继续播放关闭动效。
final ValueNotifier<double> cardDismissProgress = ValueNotifier<double>(0);

/// 卡片拖动手势的水平位移（0..屏宽）。拖动中卡片左缘跟随该值，
/// 完全跟手；松手后由 _EdgeSwipeDismissState 的 settle 动画驱动归位。
final ValueNotifier<double> cardDismissOffset = ValueNotifier<double>(0);

/// 边缘拖动手势是否激活（拖动中或归位动画中）。
/// 全屏播放器等透明路由据此采用"卡片式"跟手 rect（随手指位移+收缩）。
bool edgeDragActive = false;

/// 拖拽/回弹动画接管期间，禁止路由动画继续参与过渡计算，
/// 否则 Navigator 反向动画会把已收拢的卡片先弹回全屏再关闭。
bool cardDismissLocked = false;

/// 二级页统一转场：从卡片矩形展开（有矩形时），否则上滑 + 淡入。
/// 页面级动画只允许出现在 PlayerScreen 内部，由 player_expand_test
/// 文本守卫校验，因此这里不使用标准 Transition 封装组件。
CustomTransitionPage<Object?> expandablePage(
  ValueKey<String> pageKey,
  Widget child, {
  Rect? expandRect,
  ui.Image? expandSnapshot,
  bool fullWidthSwipe = false,
}) {
  final expanding = expandRect != null;
  return _CardExpandPage(
    key: pageKey,
    // 普通页（无卡片展开）保持不透明：iOS 上因此能启用系统级
    // "左缘右滑返回"手势（跟手 + 从当前位置继续，浮窗缩小也由系统提供）。
    // 卡片展开页必须透明才能透视下层做矩形 morph，走自绘左缘手势。
    opaque: !expanding,
    barrierDismissible: expanding,
    barrierColor: Colors.transparent,
    transitionDuration: MotionDuration.container,
    reverseTransitionDuration: MotionDuration.normal,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      late final Widget transition;
      if (!expanding) {
        transition = AnimatedBuilder(
          animation: Listenable.merge([curved, cardDismissProgress]),
          builder: (context, child) {
            final reveal = cardDismissLocked || cardDismissProgress.value > 0
                ? 1 - cardDismissProgress.value
                : curved.value;
            return Opacity(
              opacity: reveal,
              child: Transform.translate(
                offset: Offset(0, 24 * (1 - reveal)),
                child: child,
              ),
            );
          },
          child: child,
        );
      } else {
        transition = _CardRevealTransition(
          animation: curved,
          sourceGlobalRect: expandRect,
          sourceSnapshot: expandSnapshot,
          child: child,
        );
      }
      return EdgeSwipeDismiss(
        child: transition,
        fullWidthSwipe: fullWidthSwipe,
        // 收拢成型后锁定路由反向动画，pop 后不会弹回全屏再收一遍。
        onDismissCommit: () {
          cardDismissLocked = true;
        },
      );
    },
  );
}

class _CardExpandPage extends CustomTransitionPage<Object?> {
  _CardExpandPage({
    required super.key,
    required super.child,
    required super.transitionsBuilder,
    required super.opaque,
    required super.barrierDismissible,
    super.barrierColor,
    super.transitionDuration,
    super.reverseTransitionDuration,
  });

  @override
  Route<Object?> createRoute(BuildContext context) =>
      _CardExpandRoute(page: this);
}

/// 卡片页路由：视觉收拢完成（cardDismissLocked）后再 pop 时，反向动画
/// 清零——路由与屏障立即移除，源卡片无需等一段不可见的过渡时间才能点击。
class _CardExpandRoute extends PageRoute<Object?> {
  _CardExpandRoute({required _CardExpandPage page}) : super(settings: page);

  _CardExpandPage get _page => settings as _CardExpandPage;

  @override
  bool get opaque => _page.opaque;

  @override
  bool get barrierDismissible => _page.barrierDismissible;

  @override
  Color? get barrierColor => _page.barrierColor;

  @override
  String? get barrierLabel => _page.barrierLabel;

  @override
  bool get maintainState => _page.maintainState;

  @override
  Duration get transitionDuration => _page.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _page.reverseTransitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: _page.child,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _page.transitionsBuilder(context, animation, secondaryAnimation, child);

  @override
  bool didPop(Object? result) {
    if (cardDismissLocked) {
      controller?.reverseDuration = Duration.zero;
    }
    return super.didPop(result);
  }
}

/// 从屏幕左缘右滑关闭当前页面。只在边缘窄条接管手势，避免影响页面
/// 内的横向列表、播放器 PageView 和主 Tab 滑动。
/// - 不透明路由（iOS 普通页）：不接管，交系统左缘返回手势。
/// - 透明路由（卡片展开页/播放器）：只发布 [progress]（跟手驱动
///   内层 morph），不叠加外层 transform——否则内容缩放与外层矩形
///   裁剪两条曲线打架，出现"与卡片同缩程度不一致的浮动层"。
class EdgeSwipeDismiss extends StatefulWidget {
  const EdgeSwipeDismiss({
    super.key,
    required this.child,
    this.progress,
    this.onDismissCommit,
    this.invertProgress = false,
    this.fullWidthSwipe = false,
  });

  final Widget child;

  /// 拖动进度发布目标（1 = 完全收拢）。卡片页默认全局卡片进度，
  /// 播放器传入全屏播放器路由进度。
  final ValueNotifier<double>? progress;

  /// 收拢完成后、关闭路由前的回调（宿主在此锁定反向动画接管）。
  final VoidCallback? onDismissCommit;

  /// 目标进度语义是否反转：播放器路由进度是"1=全屏、0=收拢"，
  /// 与拖动进度（0=起点、1=拖满）相反，必须取反才能让封面
  /// 从全屏随手指逐渐变小，而不是按下瞬间跳到迷你形态。
  final bool invertProgress;

  /// 整页右滑返回（用于无横向滚动内容的页面，如榜单设置）。
  /// 默认只接管左缘窄条，避免与页面内横向列表/PageView 冲突。
  final bool fullWidthSwipe;

  @override
  State<EdgeSwipeDismiss> createState() => _EdgeSwipeDismissState();
}

class _EdgeSwipeDismissState extends State<EdgeSwipeDismiss>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  // 形态进度（0..1，1 = 完全收拢成卡片）：与位移_独立，
  // 松手收拢时页面一边滑回原位一边持续收拢成卡片，绝不先放大再退出。
  double _morph = 0;
  late final ValueNotifier<double> _progress =
      widget.progress ?? cardDismissProgress;
  late final AnimationController _settleController;
  Animation<double>? _dragAnimation;
  Animation<double>? _morphAnimation;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(vsync: this)
      ..addListener(() {
        final drag = _dragAnimation;
        if (drag != null && mounted) {
          setState(() => _drag = drag.value);
        }
        final morph = _morphAnimation;
        if (morph != null) {
          _morph = morph.value;
        }
        _syncProgress();
      });
  }

  @override
  void dispose() {
    if (_progress.value != 0) {
      _progress.value = 0;
    }
    cardDismissOffset.value = 0;
    edgeDragActive = false;
    _settleController.dispose();
    super.dispose();
  }

  // 把当前形态进度发布给过渡层（跟手驱动矩形 morph）。
  void _syncProgress() {
    _progress.value = widget.invertProgress ? 1 - _morph : _morph;
    cardDismissOffset.value = _drag;
    edgeDragActive = _drag > 0 || _morph > 0;
  }

  void _settleTo({
    required double targetDrag,
    required double targetMorph,
    required Duration duration,
    VoidCallback? onStart,
    required VoidCallback onComplete,
  }) {
    _settleController
      ..stop()
      ..duration = duration;
    final curved = CurvedAnimation(
      parent: _settleController,
      // 归位/收拢带 spring 手感，与全屏播放器动效同一曲线族。
      curve: MotionCurve.iosSpring,
    );
    _dragAnimation = Tween<double>(begin: _drag, end: targetDrag).animate(curved);
    _morphAnimation = Tween<double>(
      begin: _morph,
      end: targetMorph,
    ).animate(curved);
    onStart?.call();
    _settleController.forward(from: 0);
    void settleListener(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      _settleController.removeStatusListener(settleListener);
      onComplete();
    }

    _settleController.addStatusListener(settleListener);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final route = ModalRoute.of(context);
    final opaqueRoute = route?.opaque ?? true;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    // 不透明路由（iOS 普通页）：系统左缘返回手势可用，自绘手势完全退出，
    // 过渡则直接由系统手势驱动的 route 动画播放（跟手 + 从当前位置继续）。
    final systemBackGesture = ios && opaqueRoute;
    // 透明路由（卡片展开/播放器）必须只走内层矩形 morph 一套进度，
    // 避免外层 translate/scale 与内层裁剪互相打架。
    final morphOnly = !opaqueRoute;
    final cardMorph = !opaqueRoute;
    final progress = _morph;
    final scale = morphOnly ? 1.0 : (ios ? 1 - 0.5 * progress : 1.0);
    // 圆角只在非卡片形态叠加（卡片页圆角由内层 rect 计算）。
    final radius = morphOnly ? 0.0 : 48.0 * progress;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: ios && !morphOnly && progress > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24 * progress),
                  blurRadius: 28 * progress,
                  spreadRadius: 2 * progress,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: widget.child,
      ),
    );
    final page = cardMorph
        ? surface
        : Transform.translate(
            offset: Offset(_drag, 0),
            child: Transform.scale(
              alignment: Alignment.centerLeft,
              scale: scale,
              child: surface,
            ),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        page,
        if (!systemBackGesture)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            // iOS 系统手势区约 20pt，这里略微加宽（40）提高触发成功率；
            // 卡片/播放器为透明路由，没有系统手势，窄条按平台取 32；
            // 页面无横向滚动内容时可整页右滑返回。
            right: widget.fullWidthSwipe ? 0 : null,
            width: widget.fullWidthSwipe ? null : (ios ? 40.0 : 32.0),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) {
              _settleController.stop();
              edgeDragActive = true;
            },
              onHorizontalDragUpdate: (details) {
                if (details.delta.dx <= 0 && _drag <= 0) return;
                final max = MediaQuery.sizeOf(context).width;
                setState(() {
                  _drag = (_drag + details.delta.dx).clamp(0.0, max);
                  _morph = _drag / max;
                });
                _syncProgress();
              },
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
if (_drag > width * 0.22 || velocity > 700) {
                // 从当前位置继续：页面一边滑回原位（不放大），一边持续
                // 收拢成卡片，在源卡片位置成型后 pop（宿主此时锁定
                // 反向动画接管，路由关闭不再回弹放大）。
                _settleTo(
                  targetDrag: 0,
                  targetMorph: 1,
                  duration: MotionDuration.normal,
                  onComplete: () {
                    widget.onDismissCommit?.call();
                    Navigator.of(context).maybePop();
                  },
                );
              } else {
                _settleTo(
                  targetDrag: 0,
                  targetMorph: 0,
                  duration: MotionDuration.micro,
                  onComplete: () {
                    cardDismissLocked = false;
                  },
                );
              }
            },
            onHorizontalDragCancel: () {
              _settleTo(
                targetDrag: 0,
                targetMorph: 0,
                duration: MotionDuration.micro,
                onComplete: () {
                  cardDismissLocked = false;
                },
              );
            },
            ),
          ),
      ],
    );
  }
}

class _CardRevealTransition extends StatefulWidget {
  const _CardRevealTransition({
    required this.animation,
    required this.sourceGlobalRect,
    this.sourceSnapshot,
    required this.child,
  });

  final Animation<double> animation;
  final Rect sourceGlobalRect;
  final ui.Image? sourceSnapshot;
  final Widget child;

  @override
  State<_CardRevealTransition> createState() => _CardRevealTransitionState();
}

class _CardRevealTransitionState extends State<_CardRevealTransition> {
  @override
  void dispose() {
    if (cardDismissLocked) {
      cardDismissLocked = false;
      cardDismissProgress.value = 0;
    }
    widget.sourceSnapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 卡片矩形直接使用记录时的屏幕坐标：路由页面与 Navigator 同坐标系，
    // 收拢终点即源卡片原位，避免坐标换算引入偏移。
    final sourceTopLeft = widget.sourceGlobalRect.topLeft;
    final sourceRect = sourceTopLeft & widget.sourceGlobalRect.size;
    final targetRect = Offset.zero & MediaQuery.sizeOf(context);
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.animation,
        cardDismissProgress,
        cardDismissOffset,
      ]),
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        // 拖拽接管时用跟手的 dismiss 进度驱动矩形收拢，路由动画不参与，
        // 松开后从当前位置继续播放关闭动效。
        final t = cardDismissLocked || cardDismissProgress.value > 0
            ? cardDismissProgress.value
            : 1 - widget.animation.value;
        // 单个公式同时体现"跟手位移 + 收缩"：t=0 全屏原位，
        // t=1 收拢到源卡片；中间阶段矩形中心随手指位移（t*width），
        // 因此拖动时卡片既收缩又跟随手指，不会出现外层位移与内层
        // 裁剪两条曲线打架的错位。
        final sizeW = targetRect.width - (targetRect.width - sourceRect.width) * t;
        final sizeH = targetRect.height -
            (targetRect.height - sourceRect.height) * t;
        // 跟手：拖动中卡片左缘 = 手指水平位移，手停卡停；
        // 松手动画（已锁）线性归位到源卡片位置；
        // 无拖动的正常关闭（返回按钮/系统手势）直接归位到源位置，
        // 不能再往左缘飞。
        final fingerX = cardDismissOffset.value;
        final dragging = cardDismissLocked || cardDismissProgress.value > 0;
        final left = dragging
            ? fingerX * (1 - t) + sourceRect.left * t
            : sourceRect.left * t;
        final top = sourceRect.top * t;
        final currentRect = Rect.fromLTWH(left, top, sizeW, sizeH);
        // 收拢/拖拽关闭方向（dragging）：内容保持不透明、不浮现快照，
        // 收拢矩形只是裁剪窗口——route 移除瞬间真实页面同像素接管，
        // 不会出现"快照 vs 实时渲染"的亮度跳变。
        // 展开方向保留原逻辑：内容淡出让快照盖住未长成的本体。
        final reveal = dragging
            ? 1.0
            : ((1 - t) / 0.18).clamp(0.0, 1.0);
        final snapshotOpacity = dragging
            ? 0.0
            : ((t - 0.8) / 0.2).clamp(0.0, 1.0);
        // 背景/表面圆角全程保持与源卡片一致（18），
        // 动效行进中矩形扩张/收缩不改变圆角。
        const radius = 18.0;

        // 收拢完成（t 接近 1）时提前交棒：过渡层退场，真实页面直接接管，
        // 避免末帧残留图层造成的亮度/内容跳变。
        if (dragging && t >= 0.99) {
          return const SizedBox.shrink();
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: currentRect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: reveal,
                      child: ColoredBox(color: backgroundColor),
                    ),
                    // 快照只在收尾浮现：展开起步盖住本体、收拢收尾交接。
                    if (widget.sourceSnapshot != null)
                      Opacity(
                        opacity: snapshotOpacity,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Transform.scale(
                            alignment: Alignment.topLeft,
                            // 表面可沿两个方向扩展，但卡片内的文字和图标
                            // 必须只按一个比例放大，避免被垂直拉长。
                            scale: currentRect.width / sourceRect.width,
                            child: SizedBox(
                              width: sourceRect.width,
                              height: sourceRect.height,
                              child: RawImage(
                                image: widget.sourceSnapshot,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                      ),
                    OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: targetRect.width,
                      maxWidth: targetRect.width,
                      minHeight: targetRect.height,
                      maxHeight: targetRect.height,
                      child: Opacity(
                        opacity: reveal,
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            MotionDistance.standard * t,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
