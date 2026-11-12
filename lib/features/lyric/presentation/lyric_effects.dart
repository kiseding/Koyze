// 文件说明：歌词的视觉效果——上下两侧的景深模糊、整块歌词的入场动画。
//
// 抽出来是因为这两件事都要在「真实歌词」和「设置页预览」两处一致：预览里
// 看起来糊多少、怎么进场，播放页就必须是同一个公式。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/motion/motion_tokens.dart';

/// 入场动画。索引存进设置（`lyric_entrance`），改名不会让旧选择失效。
enum LyricEntranceStyle { slideUp, fade, zoom, blur }

/// 离当前行最远处（3 行及以上）的模糊半径上限，逻辑像素。
///
/// 6 已经把 16pt 的字糊成一团色块了；再大就只剩噪点，没有「景深」可言。
const double kLyricMaxBlurSigma = 6.0;

/// 距离当前行 [distance] 行的文字该糊多少。
///
/// 当前行恒为 0——用户要读的就是它。之后线性加深，到第 3 行封顶：
/// 再远的行本来就快滚出视口，继续加模糊只是白花 GPU。
///
/// [amount] 是设置里的 0~1 档位，0 表示完全不糊。
double lyricBlurSigmaFor({required int distance, required double amount}) {
  if (amount <= 0 || distance <= 0) return 0;
  final ramp = (distance / 3).clamp(0.0, 1.0);
  return amount.clamp(0.0, 1.0) * kLyricMaxBlurSigma * ramp;
}

/// 需要时套一层高斯模糊。
///
/// 用 [ImageFiltered] 而不是 `MaskFilter`：后者只能作用在 `TextStyle.foreground`
/// 上，而 `foreground` 与 `color` 互斥，逐字高亮那套 Stack + ClipRect 会直接
/// 断言失败；`ImageFiltered` 对任何子树都成立，代价是一次 saveLayer。
Widget lyricBlurred(Widget child, double sigma) {
  if (sigma < 0.05) return child;
  return ImageFiltered(
    imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: child,
  );
}

/// 一块内容「进场」时按用户选的样式出现。
///
/// 触发有两条路径，缺一不可：
///
/// 1. [playKey] 变了——同一棵树内换了内容（歌词有缓存、不经过加载态）。
/// 2. [playOnMount] 为真时，挂载即播放——换歌一定会先经过「正在加载歌词」，
///    那段时间本组件被整个摘出树，等歌词回来是**新 State**，`value` 初始为 1，
///    `didUpdateWidget` 根本不会触发。只靠第 1 条的话，用户永远看不到动画。
///    调用方用「已经进过一次场」来区分首屏（有页面转场，不必再淡入一遍）
///    与后续换歌（值得播）。
class LyricEntrance extends StatefulWidget {
  const LyricEntrance({
    super.key,
    required this.style,
    required this.playKey,
    this.playOnMount = false,
    required this.child,
  });

  final LyricEntranceStyle style;
  final Object playKey;
  final bool playOnMount;
  final Widget child;

  @override
  State<LyricEntrance> createState() => _LyricEntranceState();
}

class _LyricEntranceState extends State<LyricEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionDuration.container,
    // 默认首帧即终态。挂载就要播时在 initState 里压回 0。
    value: widget.playOnMount ? 0 : 1,
  );

  /// 挂载时该播、但要等 `didChangeDependencies` 拿到 reduceMotion 才能定。
  late bool _pendingMountPlay = widget.playOnMount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = motionDuration(context, MotionDuration.container);
    if (!_pendingMountPlay) return;
    _pendingMountPlay = false;
    if (_controller.duration == Duration.zero) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant LyricEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.playKey, oldWidget.playKey)) return;
    if (_controller.duration == Duration.zero) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final content = child!;
        final progress = MotionCurve.easeOut.transform(
          _controller.value.clamp(0.0, 1.0),
        );
        switch (widget.style) {
          case LyricEntranceStyle.fade:
            return Opacity(opacity: progress, child: content);
          case LyricEntranceStyle.slideUp:
            return Opacity(
              opacity: 0.25 + 0.75 * progress,
              child: Transform.translate(
                offset: Offset(0, 26 * (1 - progress)),
                child: content,
              ),
            );
          case LyricEntranceStyle.zoom:
            return Opacity(
              opacity: 0.25 + 0.75 * progress,
              child: Transform.scale(
                scale: 0.96 + 0.04 * progress,
                child: content,
              ),
            );
          case LyricEntranceStyle.blur:
            if (progress >= 0.999) return content;
            return Opacity(
              opacity: 0.35 + 0.65 * progress,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 12 * (1 - progress),
                  sigmaY: 12 * (1 - progress),
                ),
                child: content,
              ),
            );
        }
      },
    );
  }
}
