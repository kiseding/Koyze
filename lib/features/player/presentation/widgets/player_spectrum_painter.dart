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
    this.revision = 0,
    super.repaint,
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

  /// 数据版本号，每次幅值更新时由调用方自增。
  ///
  /// 不能靠 `identical(display, old.display)` 判断是否需要重绘：补间是原地
  /// 修改 [display] 的元素（每帧重建一个 64 元素的 List 太浪费），于是新旧
  /// painter 持有的是**同一个 List**，identity 永远相等，`shouldRepaint`
  /// 恒为 false，CustomPaint 就永远停在第一帧——数据一直在动，画面却是静的。
  /// 也不能改用 `listEquals`：old 引用的那个 List 内容已经被改掉了，比较的
  /// 是同一份数据，同样恒为 true。只有版本号是可靠的信号。
  final int revision;

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
      case SpectrumStyle.steps:
        _paintSteps(canvas, size);
    }
  }

  /// 阶梯量化到几档。
  ///
  /// 8 档在 44px 高的条上约 5px 一级，一眼能数清级别；再多就退化成连续曲线，
  /// 再少（4 档）动态范围又太挤，安静段落整条贴底。
  static const _stepLevels = 8;

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
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        accent.withValues(alpha: 0.55),
        accent,
        Color.lerp(accent, Colors.white, 0.35)!,
      ],
      stops: const [0.0, 0.62, 1.0],
    );
    final peakColor = accent.withValues(alpha: 0.38);

    for (var i = 0; i < count; i++) {
      final value = display[i].clamp(0.0, 1.0);
      final height = math.max(1.5, value * size.height);
      final left = i * step + (step - barWidth) / 2;
      final top = size.height - height;
      final rect = Rect.fromLTWH(left, top, barWidth, height);

      // 纵向渐变：低处偏暗、高处偏亮，让「响度」有纵向的读法。
      paint.shader = gradient.createShader(rect);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );

      final peakValue = peak.length > i ? peak[i].clamp(0.0, 1.0) : value;
      final peakTop = size.height - math.max(1.5, peakValue * size.height);
      if (top - peakTop > 1.5) {
        peakPaint.color = peakColor;
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
          paint.color = Color.lerp(
            accent,
            Colors.white,
            0.10 + 0.45 * t,
          )!.withValues(alpha: 0.50 + 0.50 * t);
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

  /// 阶梯：把连续幅值吸附到有限档位，画成一条不断的楼梯轮廓。
  ///
  /// 它和柱状的分水岭不在形状而在**值域**：柱子的高度是连续的，台阶的高度
  /// 只取几个离散值，所以相邻频段常常落在同一档，连成一段真正的水平踏面。
  /// 这和「电平表」也不是一回事——电平是每列独立的小方块，列与列之间有缝；
  /// 阶梯是整条连续折线，中间不留缝，读的是一把量程尺的轮廓。
  void _paintSteps(Canvas canvas, Size size) {
    final count = display.length;
    final stepWidth = size.width / count;
    final baseline = size.height - 1;

    // 量化到 [_stepLevels] 档。round 而不是 floor：floor 会让整条在安静段落
    // 一直贴底，档位反而看不出来。
    final heights = <double>[
      for (final value in display)
        (value.clamp(0.0, 1.0) * _stepLevels).round() / _stepLevels,
    ];

    // 楼梯轮廓：每列先垂直上去，再水平走到下一列起点。相邻同档的两列因此
    // 连成一段长踏面，肉眼一眼能看出「跳了一级」。
    final topLine = Path()..moveTo(0, baseline - heights.first * baseline);
    for (var i = 0; i < count; i++) {
      final top = baseline - heights[i] * baseline;
      topLine
        ..lineTo(i * stepWidth, top)
        ..lineTo((i + 1) * stepWidth, top);
    }

    final body = Path.from(topLine)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            accent.withValues(alpha: 0.44),
            accent.withValues(alpha: 0.92),
          ],
        ).createShader(Offset.zero & size),
    );

    // 踏面高光：只描上边界。它同时干了两件事——把相邻两级的落差强调出来，
    // 也压住折线的毛边，让台阶看起来是「切」出来的而不是「糊」出来的。
    canvas.drawPath(
      topLine,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeJoin = StrokeJoin.miter
        ..color = Color.lerp(
          accent,
          Colors.white,
          0.40,
        )!.withValues(alpha: 0.92),
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
      oldDelegate.revision != revision;
}
