import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/player_spectrum_settings.dart';

/// 画一条频谱。
///
/// 输入是已经补间过的 [display]（见 `PlayerSpectrumStrip` 的逐帧指数逼近），
/// 因此这里只管几何，不再碰时间。`SpectrumStyle` 决定形状。
///
/// 五种样式刻意走**不同的几何读法**，而不是同一根柱子换圆角或换个填充：
/// 柱状读包络、电平读档位、光点读位移、山脊读纵深、光带读厚度。这样换样式
/// 时看到的是另一种「乐器」，而不是同一件东西的皮肤。
class SpectrumPainter extends CustomPainter {
  const SpectrumPainter({
    required this.display,
    required this.peak,
    required this.style,
    required this.accent,
    required this.trackColor,
  });

  /// 幅值，长度即频段数量。
  final List<double> display;

  /// 峰值帽的位置，只对 [SpectrumStyle.bars] 有意义。
  final List<double> peak;

  final SpectrumStyle style;

  /// 主色，通常是主题的强调色。
  final Color accent;

  /// 轨道色。用于空态底纹与电平表的未点亮格。
  final Color trackColor;

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
        _paintBars(canvas, size);
      case SpectrumStyle.leds:
        _paintLeds(canvas, size);
      case SpectrumStyle.dots:
        _paintDots(canvas, size);
      case SpectrumStyle.ridges:
        _paintRidges(canvas, size);
      case SpectrumStyle.halo:
        _paintHalo(canvas, size);
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

  /// 柱状：最直白的包络读法。
  void _paintBars(Canvas canvas, Size size) {
    final count = display.length;
    final step = size.width / count;
    final barWidth = math.max(2.0, step * 0.58);
    final radius = math.min(barWidth / 2, 2.0);
    final paint = Paint()..style = PaintingStyle.fill;
    final peakPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final value = display[i].clamp(0.0, 1.0);
      final height = math.max(1.5, value * size.height);
      final left = i * step + (step - barWidth) / 2;
      final top = size.height - height;
      final rect = Rect.fromLTWH(left, top, barWidth, height);

      // 纵向渐变：低处偏暗、高处偏亮，让「响度」有纵向的读法。
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

  /// 电平表：一列离散方块，点亮的格数即幅值。
  ///
  /// 未点亮的格用极暗的轨道色保留着，整条看起来像一块真的表盘——这是它
  /// 和柱状最大的区别：柱状只画有声的那一段，电平表把「量程」也画出来。
  void _paintLeds(Canvas canvas, Size size) {
    final count = display.length;
    final step = size.width / count;
    final cell = math.max(2.0, step * 0.66);
    const rowHeight = 2.2;
    const rowGap = 2.0;
    const pitch = rowHeight + rowGap;
    final rows = math.max(1, ((size.height + rowGap) / pitch).floor());
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final value = display[i].clamp(0.0, 1.0);
      final lit = (value * rows).ceil().clamp(0, rows);
      final left = i * step + (step - cell) / 2;

      for (var row = 0; row < rows; row++) {
        final bottom = size.height - row * pitch;
        final rect = Rect.fromLTRB(
          left,
          bottom - rowHeight,
          left + cell,
          bottom,
        );
        if (row < lit) {
          // 越靠上的格子越亮：这是「已经冲到这一档」的提示。
          final t = rows <= 1 ? 1.0 : row / (rows - 1);
          paint.color = Color.lerp(accent, Colors.white, 0.10 + 0.45 * t)!
              .withValues(alpha: 0.50 + 0.50 * t);
        } else {
          paint.color = trackColor.withValues(alpha: 0.14);
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(0.9)),
          paint,
        );
      }
    }
  }

  /// 光点：每列一个浮动的圆点，纵向位置编码幅值，底部拖一条尾线。
  ///
  /// 它读的是「位移」而不是「高度」，所以即便幅值一样，观感也和柱状完全不同
  /// ——柱子是面积在变，光点是位置在动。
  void _paintDots(Canvas canvas, Size size) {
    final count = display.length;
    final step = size.width / count;
    final trail = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final value = display[i].clamp(0.0, 1.0);
      final radius = math.min(step * 0.30, 1.3 + value * 2.1);
      final x = step / 2 + i * step;
      final y = size.height - radius - value * (size.height - 2 * radius);

      trail.color = accent.withValues(alpha: 0.10 + 0.20 * value);
      canvas.drawLine(Offset(x, y + radius), Offset(x, size.height), trail);

      // 外圈柔光 + 内圈实体，给一点「发光」的体积感，而不是硬边圆。
      dot.color = accent.withValues(alpha: 0.16 + 0.14 * value);
      canvas.drawCircle(Offset(x, y), radius * 2.0, dot);
      dot.color = Color.lerp(accent, Colors.white, 0.32)!;
      canvas.drawCircle(Offset(x, y), radius, dot);
    }
  }

  /// 山脊：三层同形状、不同高度与亮度的曲线叠在一起。
  ///
  /// 后层更高更暗、前层更矮更亮，观感上像远山压着近山。三层共用同一份数据，
  /// 不做相位偏移——偏移会让它看起来像随机噪声，反而不像地形。
  void _paintRidges(Canvas canvas, Size size) {
    final count = display.length;
    if (count < 2) return;
    final step = size.width / (count - 1);
    const scales = <double>[1.0, 0.76, 0.52];
    const alphas = <double>[0.30, 0.48, 0.95];

    for (var layer = 0; layer < scales.length; layer++) {
      final points = <Offset>[];
      for (var i = 0; i < count; i++) {
        final value = (display[i] * scales[layer]).clamp(0.0, 1.0);
        points.add(Offset(i * step, size.height - value * (size.height - 2)));
      }
      final outline = _smoothPath(points);
      final fill = Path.from(outline)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();

      canvas.drawPath(
        fill,
        Paint()
          ..style = PaintingStyle.fill
          ..color = accent.withValues(alpha: alphas[layer] * 0.28),
      );
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = accent.withValues(alpha: alphas[layer]),
      );
    }
  }

  /// 光环：上下边界围成一个闭合的「线框」，只有描边，不填色。
  ///
  /// 这是五种里唯一一个**看轮廓**而不是看面积的：带子变厚时线框张开，变薄时
  /// 收成一条线。刻意空心——一旦填色就会和山脊撞脸，两者必须是「线」和
  /// 「块」的区别。
  void _paintHalo(Canvas canvas, Size size) {
    final count = display.length;
    if (count < 2) return;
    final step = size.width / (count - 1);

    final top = <Offset>[];
    final bottom = <Offset>[];
    for (var i = 0; i < count; i++) {
      final value = display[i].clamp(0.0, 1.0);
      final thickness = size.height * (0.10 + 0.46 * value);
      final center = size.height * (0.52 - 0.08 * value);
      top.add(Offset(i * step, center - thickness / 2));
      bottom.add(Offset(i * step, center + thickness / 2));
    }

    final loop = _smoothPath(top);
    for (var i = count - 1; i > 0; i--) {
      final current = bottom[i];
      final previous = bottom[i - 1];
      loop.quadraticBezierTo(
        current.dx,
        current.dy,
        (current.dx + previous.dx) / 2,
        (current.dy + previous.dy) / 2,
      );
    }
    loop
      ..quadraticBezierTo(
        bottom.first.dx,
        bottom.first.dy,
        bottom.first.dx,
        bottom.first.dy,
      )
      ..close();

    // 三层描边叠出「灯管」的发光：外层宽而淡、中层收紧、内芯最亮。
    canvas.drawPath(
      loop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round
        ..color = accent.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      loop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..color = accent.withValues(alpha: 0.30),
    );
    canvas.drawPath(
      loop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(accent, Colors.white, 0.55)!
            .withValues(alpha: 0.96),
    );
  }

  /// 二次贝塞尔平滑：控制点取当前点、终点取相邻两点的中点。
  ///
  /// 比 `Catmull-Rom` 简单，但足够把几十个点连成一条没有硬折角的线，
  /// 而且不会过冲——频谱曲线过冲会长出数据里不存在的尖峰。
  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      path.quadraticBezierTo(
        current.dx,
        current.dy,
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
    }
    final last = points.last;
    path.lineTo(last.dx, last.dy);
    return path;
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.accent != accent ||
      oldDelegate.trackColor != trackColor ||
      !identical(oldDelegate.display, display) ||
      !identical(oldDelegate.peak, peak);
}
