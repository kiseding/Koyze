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

/// 卡片拖拽关闭进度（0..1，1 = 完全收起成卡片）。
/// EdgeSwipeDismiss 拖动时实时写入，_CardRevealTransition 据此让
/// 矩形 morph 跟手收拢，松开后从当前位置继续播放关闭动效。
final ValueNotifier<double> cardDismissProgress = ValueNotifier<double>(0);

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
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(vsync: this)
      ..addListener(() {
        final animation = _settleAnimation;
        if (animation != null && mounted) {
          setState(() => _drag = animation.value);
          _syncProgress();
        }
      });
  }

  @override
  void dispose() {
    if (_locked) {
      cardDismissLocked = false;
      cardDismissProgress.value = 0;
    }
    _settleController.dispose();
    super.dispose();
  }

  // 只有本人（本次路由）持有锁；避免并行路由互相干扰。
  void _syncProgress() {
    final width = MediaQuery.sizeOf(context).width;
    cardDismissProgress.value =
        width == 0 ? 0.0 : (_drag / width).clamp(0.0, 1.0);
  }

  void _settleTo(
    double target,
    Duration duration, {
    VoidCallback? onStart,
    required VoidCallback onComplete,
  }) {
    cardDismissLocked = _locked = true;
    _settleController
      ..stop()
      ..duration = duration;
    _settleAnimation = Tween<double>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _settleController, curve: MotionCurve.easeOut),
    );
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
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final progress = width == 0 ? 0.0 : (_drag / width).clamp(0.0, 1.0);
    final scale = ios ? 1 - 0.5 * progress : 1.0;
    // 圆角所有平台都跟手：拖动时页面边缘实时圆角化（0 → 48）。
    final radius = 48.0 * progress;
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
              _syncProgress();
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (_drag > width * 0.22 || velocity > 700) {
                // 先让页面从拖动位置流畅"归位"（滑回原位、卡片恢复全屏），
                // 归位完成后再 pop，由路由反向动画播放正常的收拢关闭动效。
                _settleTo(
                  0,
                  MotionDuration.normal,
                  onComplete: () {
                    cardDismissLocked = _locked = false;
                    Navigator.of(context).maybePop();
                  },
                );
              } else {
                _settleTo(
                  0,
                  MotionDuration.micro,
                  onComplete: () {
                    cardDismissLocked = _locked = false;
                  },
                );
              }
            },
            onHorizontalDragCancel: () {
              _settleTo(
                0,
                MotionDuration.micro,
                onComplete: () {
                  cardDismissLocked = _locked = false;
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
    final overlayBox =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    final sourceTopLeft =
        overlayBox?.globalToLocal(widget.sourceGlobalRect.topLeft) ??
        widget.sourceGlobalRect.topLeft;
    final sourceRect = sourceTopLeft & widget.sourceGlobalRect.size;
    final targetRect = Offset.zero & MediaQuery.sizeOf(context);
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return AnimatedBuilder(
      animation: Listenable.merge([widget.animation, cardDismissProgress]),
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        // 拖拽接管时用跟手的 dismiss 进度驱动矩形收拢，路由动画不参与，
        // 松开后从当前位置继续播放关闭动效。
        final t = cardDismissLocked || cardDismissProgress.value > 0
            ? 1 - cardDismissProgress.value
            : widget.animation.value;
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
