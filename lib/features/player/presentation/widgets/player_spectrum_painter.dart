import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/player_spectrum_settings.dart';

/// 画一条频谱。
///
/// 输入是已经补间过的 [display]（见 `PlayerSpectrumStrip` 的逐帧指数逼近），
/// 因此这里只管几何，不再碰时间。`SpectrumStyle` 决定形状。
class SpectrumPainter extends CustomPainter {
  const SpectrumPainter({
    required this.display,
    required this.peak,
    required this.style,
    required this.accent,
    required this.trackColor,
    this.mirroredGap = 1.5,
  });

  /// 幅值，长度即柱子数量。
  final List<double> display;

  /// 峰值帽的位置，只对 [SpectrumStyle.bars] 有意义。
  final List<double> peak;

  final SpectrumStyle style;

  /// 主色，通常是主题的 `colorScheme.primary`。
  final Color accent;

  /// 轨道色。用于空态底纹与未达到峰值的部分。
  final Color trackColor;

  /// [SpectrumStyle.mirror] 上下两半之间的间隙（像素）。
  final double mirroredGap;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 没有数据时画一排等高的轨道柱：这块区域仍然是一条「频谱条」，
    // 而不是一片空白，布局与语义都不变。
    if (display.isEmpty) {
      _paintIdle(canvas, size);
      return;
    }

    switch (style) {
      case SpectrumStyle.bars:
        _paintBars(canvas, size, rounded: false);
      case SpectrumStyle.pills:
        _paintBars(canvas, size, rounded: true);
      case SpectrumStyle.mirror:
        _paintMirror(canvas, size);
      case SpectrumStyle.wave:
        _paintWave(canvas, size, ribbon: false);
      case SpectrumStyle.ribbon:
        _paintWave(canvas, size, ribbon: true);
    }
  }

  void _paintIdle(Canvas canvas, Size size) {
    final count = 56;
    final step = size.width / count;
    final width = math.max(1.5, step * 0.42);
    final paint = Paint()..color = trackColor.withValues(alpha: 0.55);
    for (var i = 0; i < count; i++) {
      final left = i * step + (step - width) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - 2, width, 2),
          Radius.circular(width / 2),
        ),
        paint,
      );
    }
  }

  void _paintBars(Canvas canvas, Size size, {required bool rounded}) {
    final count = display.length;
    final step = size.width / count;
    final barWidth = rounded
        ? math.max(1.5, step * 0.42)
        : math.max(2.0, step * 0.58);
    final radius = rounded ? barWidth / 2 : math.min(barWidth / 2, 2.0);
    final paint = Paint()..style = PaintingStyle.fill;
    final peakPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final value = display[i].clamp(0.0, 1.0);
      final height = math.max(rounded ? barWidth : 1.5, value * size.height);
      final left = i * step + (step - barWidth) / 2;
      final top = size.height - height;
      final rect = Rect.fromLTWH(left, top, barWidth, height);

      // 纵向渐变：低处偏暗、高处偏亮，让「响度」有纵向的读法，
      // 而不是一根纯度相同的条。
      paint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          accent.withValues(alpha: 0.55),
          accent,
          Color.lerp(accent, Colors.white, 0.35)!,
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(rect);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );

      if (!rounded) {
        final peakValue = peak.length > i ? peak[i].clamp(0.0, 1.0) : value;
        final peakTop = size.height - math.max(1.5, peakValue * size.height);
        if (top - peakTop > 1.5) {
          peakPaint.color = accent.withValues(alpha: 0.38);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, peakTop - 1.5, barWidth, 1.5),
              const Radius.circular(1),
            ),
            peakPaint,
          );
        }
      }
    }
  }

  void _paintMirror(Canvas canvas, Size size) {
    final count = display.length;
    final step = size.width / count;
    final barWidth = math.max(1.5, step * 0.46);
    final half = size.height / 2;
    final gap = mirroredGap / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final value = display[i].clamp(0.0, 1.0);
      final height = math.max(1.0, value * (half - gap));
      final left = i * step + (step - barWidth) / 2;
      final full = Rect.fromLTWH(left, half - gap - height, barWidth, height * 2 + gap * 2);

      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(accent, Colors.white, 0.45)!,
          accent,
          Color.lerp(accent, Colors.white, 0.45)!,
        ],
      ).createShader(full);

      final radius = Radius.circular(barWidth / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, half - gap - height, barWidth, height),
          radius,
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, half + gap, barWidth, height),
          radius,
        ),
        paint,
      );
    }
  }

  void _paintWave(Canvas canvas, Size size, {required bool ribbon}) {
    final count = display.length;
    if (count < 2) return;
    final step = size.width / (count - 1);
    final half = size.height / 2;

    final upper = <Offset>[];
    for (var i = 0; i < count; i++) {
      final value = display[i].clamp(0.0, 1.0);
      final amplitude = ribbon ? value * (half - 1) : value * (size.height - 2);
      upper.add(
        Offset(i * step, ribbon ? half - amplitude : size.height - amplitude),
      );
    }

    Path smooth(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 0; i < points.length - 1; i++) {
        final current = points[i];
        final next = points[i + 1];
        final midX = (current.dx + next.dx) / 2;
        final midY = (current.dy + next.dy) / 2;
        path.quadraticBezierTo(current.dx, current.dy, midX, midY);
        if (i == points.length - 2) {
          path.quadraticBezierTo(next.dx, next.dy, next.dx, next.dy);
        }
      }
      return path;
    }

    final outline = smooth(upper);
    final fill = Path.from(outline);
    if (ribbon) {
      for (var i = upper.length - 1; i >= 0; i--) {
        fill.lineTo(upper[i].dx, 2 * half - upper[i].dy);
      }
    } else {
      fill
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    }
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: ribbon ? 0.85 : 0.75),
            accent.withValues(alpha: 0.16),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );

    // 只描上边界：mirror/ribbon 的下边界是对称的，再描一遍会显得脏。
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = accent.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.accent != accent ||
      oldDelegate.trackColor != trackColor ||
      !identical(oldDelegate.display, display) ||
      !identical(oldDelegate.peak, peak);
}