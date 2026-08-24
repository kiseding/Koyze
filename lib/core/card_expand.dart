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
    final snapshot = await boundary.toImage(pixelRatio: 1);
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

/// 二级页统一转场：从卡片矩形展开（有矩形时），否则上滑 + 淡入。
/// 页面级动画只允许出现在 PlayerScreen 内部，由 player_expand_test
/// 文本守卫校验，因此这里不使用标准 Transition 封装组件。
CustomTransitionPage<Object?> expandablePage(
  ValueKey<String> pageKey,
  Widget child, {
  Rect? expandRect,
  ui.Image? expandSnapshot,
}) {
  final expanding = expandRect != null;
  return CustomTransitionPage<Object?>(
    key: pageKey,
    // iOS 侧滑会把页面缩成悬浮窗口，需要持续绘制下层页面。
    opaque: !expanding && defaultTargetPlatform != TargetPlatform.iOS,
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
          animation: curved,
          builder: (context, child) => Opacity(
            opacity: curved.value,
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - curved.value)),
              child: child,
            ),
          ),
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
      return EdgeSwipeDismiss(child: transition);
    },
  );
}

/// 从屏幕左缘右滑关闭当前页面。只在 24px 边缘接管手势，避免影响页面
/// 内的横向列表、播放器 PageView 和主 Tab 滑动。
class EdgeSwipeDismiss extends StatefulWidget {
  const EdgeSwipeDismiss({super.key, required this.child});

  final Widget child;

  @override
  State<EdgeSwipeDismiss> createState() => _EdgeSwipeDismissState();
}

class _EdgeSwipeDismissState extends State<EdgeSwipeDismiss>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(vsync: this)
      ..addListener(() {
        final animation = _settleAnimation;
        if (animation != null && mounted) {
          setState(() => _drag = animation.value);
        }
      });
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  void _settleTo(double target, Duration duration, {VoidCallback? onStart}) {
    _settleController
      ..stop()
      ..duration = duration;
    _settleAnimation = Tween<double>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _settleController, curve: MotionCurve.easeOut),
    );
    onStart?.call();
    _settleController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final progress = width == 0 ? 0.0 : (_drag / width).clamp(0.0, 1.0);
    final scale = ios ? 1 - 0.5 * progress : 1.0;
    final radius = ios ? 48.0 * progress : 0.0;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: ios && progress > 0
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
    final page = Transform.translate(
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
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _settleController.stop(),
            onHorizontalDragUpdate: (details) {
              if (details.delta.dx <= 0 && _drag <= 0) return;
              setState(() {
                _drag = (_drag + details.delta.dx).clamp(0.0, width);
              });
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (_drag > width * 0.22 || velocity > 700) {
                _settleTo(
                  0,
                  MotionDuration.normal,
                  onStart: () => Navigator.of(context).maybePop(),
                );
              } else {
                _settleTo(0, MotionDuration.micro);
              }
            },
            onHorizontalDragCancel: () => _settleTo(0, MotionDuration.micro),
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
    widget.sourceSnapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlayBox =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    final sourceTopLeft =
        overlayBox?.globalToLocal(widget.sourceGlobalRect.topLeft) ??
        widget.sourceGlobalRect.topLeft;
    final sourceRect = sourceTopLeft & widget.sourceGlobalRect.size;
    final targetRect = Offset.zero & MediaQuery.sizeOf(context);
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return AnimatedBuilder(
      animation: widget.animation,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final t = widget.animation.value;
        final rectT = MotionCurve.easeOut.transform(t);
        final surfaceT = (t / 0.22).clamp(0.0, 1.0);
        final contentT = ((t - 0.18) / 0.82).clamp(0.0, 1.0);
        final snapshotT = (1 - ((t - 0.16) / 0.34)).clamp(0.0, 1.0);
        final currentRect = Rect.lerp(sourceRect, targetRect, rectT)!;
        final radius = 18.0 * (1 - rectT);

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
                      opacity: surfaceT,
                      child: ColoredBox(color: backgroundColor),
                    ),
                    if (widget.sourceSnapshot != null)
                      Opacity(
                        opacity: snapshotT,
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
                        opacity: contentT,
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            MotionDistance.standard * (1 - contentT),
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
