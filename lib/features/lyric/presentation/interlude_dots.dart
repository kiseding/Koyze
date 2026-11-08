/// 间奏呼吸点。
///
/// 一段长间奏里，歌词列表没有任何一行在唱，界面会显得"死"了几秒。这里画三个
/// 呼吸缩放的圆点把这段时间填上——视觉语言来自 AMLL 的 `InterludeDots`，
/// 状态完全由「当前时间 + 间奏区间」解析求值，不累加 delta，因此拖动进度条、
/// 切后台回来都不会漂移。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

double _clamp(double x, double min, double max) =>
    x < min ? min : (x > max ? max : x);
double _clamp01(double x) => _clamp(x, 0, 1);
double _clampPositive(double x) => x < 0 ? 0 : x;

double _easeInOutBack(double x) {
  const c1 = 1.70158;
  const c2 = c1 * 1.525;
  return x < 0.5
      ? (math.pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2
      : (math.pow(2 * x - 2, 2) * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2;
}

double _easeOutExpo(double x) =>
    x == 1 ? 1 : 1 - math.pow(2, -10 * x).toDouble();

/// 间奏点的瞬时状态。
@immutable
class InterludeDotsState {
  const InterludeDotsState({required this.scale, required this.dotOpacities});

  static const InterludeDotsState hidden = InterludeDotsState(
    scale: 0,
    dotOpacities: <double>[0, 0, 0],
  );

  /// 整体缩放。
  final double scale;

  /// 三个点各自的不透明度。
  final List<double> dotOpacities;

  bool get isVisible => scale > 0.01;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InterludeDotsState) return false;
    if (other.scale != scale) return false;
    if (other.dotOpacities.length != dotOpacities.length) return false;
    for (var i = 0; i < dotOpacities.length; i++) {
      if (other.dotOpacities[i] != dotOpacities[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(scale, Object.hashAll(dotOpacities));
}

/// 间奏点的动画解算器。
abstract final class InterludeDotsAnimation {
  /// 呼吸周期的目标时长。
  static const double targetBreatheDuration = 1500;

  /// 求 [currentTimeMs] 处的状态。
  static InterludeDotsState stateAt({
    required int currentTimeMs,
    required int startTime,
    required int endTime,
  }) {
    final interludeDuration = (endTime - startTime).toDouble();
    if (interludeDuration <= 0) return InterludeDotsState.hidden;

    final currentDuration = (currentTimeMs - startTime).toDouble();
    if (currentDuration < 0 || currentDuration > interludeDuration) {
      return InterludeDotsState.hidden;
    }

    final breatheCount = (interludeDuration / targetBreatheDuration).ceil();
    final breatheDuration = interludeDuration / breatheCount;

    var scale = 1.0;
    var globalOpacity = 1.0;

    // 呼吸：正弦轻微起伏。
    scale *=
        math.sin(1.5 * math.pi - (currentDuration / breatheDuration) * 2) / 20 +
        1;

    // 进场缩放。
    if (currentDuration < 2000) {
      scale *= _easeOutExpo(_clamp01(currentDuration / 2000));
    }

    // 进场渐显。
    if (currentDuration < 500) {
      globalOpacity = 0;
    } else if (currentDuration < 1000) {
      globalOpacity *= (currentDuration - 500) / 500;
    }

    // 退场回弹缩放。
    final remaining = interludeDuration - currentDuration;
    if (remaining < 750) {
      scale *= 1 - _easeInOutBack(_clamp01((750 - remaining) / 750 / 2));
    }
    // 退场渐隐。
    if (remaining < 375) {
      globalOpacity *= _clamp01(remaining / 375);
    }

    final dotsDuration = _clampPositive(interludeDuration - 750);
    scale = _clampPositive(scale) * 0.7;

    double rawDotOpacity(double t) {
      if (dotsDuration <= 0) return 0.25;
      return _clamp((t * 3 / dotsDuration) * 0.75, 0.25, 1);
    }

    double finalize(double v) => _clamp01(globalOpacity * v);

    return InterludeDotsState(
      scale: scale,
      dotOpacities: <double>[
        finalize(rawDotOpacity(currentDuration)),
        finalize(rawDotOpacity(currentDuration - dotsDuration / 3)),
        finalize(rawDotOpacity(currentDuration - (dotsDuration / 3) * 2)),
      ],
    );
  }
}

/// 三个点的绘制。
class InterludeDotsPainter extends CustomPainter {
  const InterludeDotsPainter({
    required this.state,
    required this.color,
    this.dotSize = 4,
    this.gap = 5,
    this.alignRight = false,
  });

  final InterludeDotsState state;
  final Color color;
  final double dotSize;
  final double gap;

  /// 对唱时靠右对齐。
  final bool alignRight;

  /// 三个点排布所需的宽度。
  static double widthFor(double dotSize, double gap) =>
      dotSize * 3 + gap * 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (!state.isVisible) return;

    final totalWidth = widthFor(dotSize, gap);
    final originX = alignRight ? size.width - totalWidth : 0.0;
    final centerY = size.height / 2;

    canvas.save();
    // 以整组的中心为锚点缩放。
    final anchorX = originX + totalWidth / 2;
    canvas.translate(anchorX, centerY);
    canvas.scale(state.scale);
    canvas.translate(-anchorX, -centerY);

    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 3; i++) {
      final opacity = i < state.dotOpacities.length
          ? state.dotOpacities[i]
          : 0.0;
      if (opacity <= 0.001) continue;
      paint.color = color.withValues(alpha: color.a * opacity);
      final cx = originX + dotSize / 2 + i * (dotSize + gap);
      canvas.drawCircle(Offset(cx, centerY), dotSize / 2, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(InterludeDotsPainter old) =>
      old.state != state ||
      old.color != color ||
      old.dotSize != dotSize ||
      old.gap != gap ||
      old.alignRight != alignRight;
}

/// 一组会自己呼吸的间奏点。
///
/// 只在 [start] ~ [end] 这段区间内推进动画：区间外停掉 ticker、只留一个低频
/// 定时器等区间开始。整段歌词里可能只有两三处间奏，让 ticker 一直空转等于
/// 白白把引擎顶在 60fps。
class InterludeDots extends StatefulWidget {
  const InterludeDots({
    super.key,
    required this.start,
    required this.end,
    required this.position,
    required this.color,
    this.dotSize = 4.5,
    this.gap = 5,
  });

  /// 间奏区间（含端点）。
  final Duration start;
  final Duration end;

  /// 每帧读取播放位置；读的是歌词时间轴（已叠加用户校准偏移）。
  final Duration Function() position;

  final Color color;
  final double dotSize;
  final double gap;

  @override
  State<InterludeDots> createState() => _InterludeDotsState();
}

class _InterludeDotsState extends State<InterludeDots>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<InterludeDotsState> _state = ValueNotifier(
    InterludeDotsState.hidden,
  );
  Ticker? _ticker;
  Timer? _wakeTimer;
  bool _ticking = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(InterludeDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start || oldWidget.end != widget.end) {
      _sync();
    }
  }

  @override
  void dispose() {
    _wakeTimer?.cancel();
    _ticker?.dispose();
    _state.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final now = widget.position();
    if (now >= widget.start && now <= widget.end) {
      _startTicking();
    } else {
      _stopTicking();
      _state.value = InterludeDotsState.hidden;
      // 轮询而不是精确排程：位置来自播放器，可能被拖动/跳转改写，
      // 排一个「到点再醒」的定时器会因为跳转而失效。
      _wakeTimer?.cancel();
      _wakeTimer = Timer(const Duration(milliseconds: 250), _sync);
    }
  }

  void _startTicking() {
    if (_ticking) return;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _ticking = true;
    _ticker ??= createTicker(_onTick);
    _ticker!.start();
  }

  void _stopTicking() {
    if (!_ticking) return;
    _ticking = false;
    _ticker?.stop();
  }

  void _onTick(Duration _) {
    final now = widget.position();
    if (now > widget.end) {
      _stopTicking();
      _state.value = InterludeDotsState.hidden;
      _wakeTimer?.cancel();
      _wakeTimer = Timer(const Duration(milliseconds: 250), _sync);
      return;
    }
    final next = InterludeDotsAnimation.stateAt(
      currentTimeMs: now.inMilliseconds,
      startTime: widget.start.inMilliseconds,
      endTime: widget.end.inMilliseconds,
    );
    if (next != _state.value) _state.value = next;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: InterludeDotsPainter.widthFor(widget.dotSize, widget.gap),
      height: widget.dotSize * 3,
      child: CustomPaint(
        painter: _LiveInterludeDotsPainter(
          state: _state,
          color: widget.color,
          dotSize: widget.dotSize,
          gap: widget.gap,
        ),
      ),
    );
  }
}

/// 直接监听 [ValueNotifier] 重绘的画笔包装。
///
/// 用 `repaint` 而不是每帧 `setState`：间奏点是一段连续动画，重建 Widget
/// 树没有意义，能重绘一次画布就够了。
class _LiveInterludeDotsPainter extends CustomPainter {
  _LiveInterludeDotsPainter({
    required this.state,
    required this.color,
    required this.dotSize,
    required this.gap,
  }) : super(repaint: state);

  final ValueListenable<InterludeDotsState> state;
  final Color color;
  final double dotSize;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    InterludeDotsPainter(
      state: state.value,
      color: color,
      dotSize: dotSize,
      gap: gap,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_LiveInterludeDotsPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.color != color ||
      oldDelegate.dotSize != dotSize ||
      oldDelegate.gap != gap;
}
