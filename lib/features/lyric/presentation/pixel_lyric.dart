// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 像素歌词的栅格字号。
///
/// 越小越"颗粒"，但小到一定程度汉字就糊成黑块——11 是「还认得出字」的下限。
/// 这个值同时也是栅格化的逻辑字号：栅格化后按 [kPixelLyricScale] 放大回正常
/// 大小，字形边缘因此是硬边方块。
const double kPixelLyricGridSize = 11;

/// 栅格图放大回目标尺寸的倍数。
///
/// 与 [kPixelLyricGridSize] 相乘约等于正常歌词字号（16~22），否则一行像素歌词
/// 的高度会和列表里其它行对不上，滚动时看得到抖动。
const double kPixelLyricScale = 1.8;

/// 一行像素歌词的绘制高度。
double pixelLyricLineHeight(double scale) =>
    kPixelLyricGridSize * kPixelLyricScale * 1.5 * scale + 12;

/// 把一行文字渲染成真正的点阵图。
///
/// 关键在于「先小后大」：用 [ui.Paragraph] 在 11px 下渲染，再交给
/// [FilterQuality.none] 放大。直接给大字设 `FilterQuality.none` 没有效果——
/// Flutter 不会把字形像素化，必须真的先得到一张小图。
///
/// 栅格图一律画成白色，颜色在绘制时用 [ColorFilter] 染上去。这样「已唱」
/// 「未唱」两种颜色共用同一份栅格图，缓存命中率翻倍。
class PixelLyricPainter extends CustomPainter {
  PixelLyricPainter({
    required this.text,
    required this.color,
    this.fontWeight = FontWeight.bold,
    this.textAlign = TextAlign.center,
    this.scale = 1,
  });

  final String text;
  final Color color;
  final FontWeight fontWeight;
  final TextAlign textAlign;

  /// 用户字号倍率。栅格图不变，只改绘制时的放大倍数。
  final double scale;

  static final Map<String, ui.Image> _cache = <String, ui.Image>{};
  static const int _cacheLimit = 96;

  /// 清空缓存。测试里换字体或改语言时会用；生产环境不需要。
  static void clearCache() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }

  /// 取（或生成）这一行文字的栅格图。
  ///
  /// 返回 null 表示引擎还没准备好栅格化。调用方应当退回普通文字，不能让歌词
  /// 整行消失。
  static ui.Image? imageFor(String text, FontWeight fontWeight) {
    final key = '$text|$fontWeight';
    final cached = _cache[key];
    if (cached != null) return cached;

    final image = _rasterize(text, fontWeight);
    if (image == null) return null;
    _cache[key] = image;
    if (_cache.length > _cacheLimit) {
      // 先进先出：歌词滚动时被淘汰的通常是很久没出现的那几行。
      final oldest = _cache.keys.first;
      _cache.remove(oldest)?.dispose();
    }
    return image;
  }

  static ui.Image? _rasterize(String text, FontWeight fontWeight) {
    try {
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontSize: kPixelLyricGridSize,
                fontWeight: fontWeight,
                maxLines: 1,
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: const Color(0xFFFFFFFF),
                fontSize: kPixelLyricGridSize,
                fontWeight: fontWeight,
              ),
            )
            ..addText(text);
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 16384));

      final width = paragraph.maxIntrinsicWidth.ceil().clamp(1, 4096);
      final height = paragraph.height.ceil().clamp(1, 256);

      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawParagraph(paragraph, Offset.zero);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      return image;
    } on Object {
      return null;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final image = text.isEmpty ? null : imageFor(text, fontWeight);
    if (image == null) {
      _paintFallback(canvas, size);
      return;
    }
    paintPixelImage(
      canvas,
      size,
      image,
      color: color,
      textAlign: textAlign,
      scale: scale,
    );
  }

  /// 把栅格图按 [scale] 放大画到 [size] 中央。
  static void paintPixelImage(
    Canvas canvas,
    Size size,
    ui.Image image, {
    required Color color,
    required TextAlign textAlign,
    required double scale,
  }) {
    final width = image.width * kPixelLyricScale * scale;
    final height = image.height * kPixelLyricScale * scale;
    final left = switch (textAlign) {
      TextAlign.left || TextAlign.start => 0.0,
      TextAlign.right || TextAlign.end => size.width - width,
      _ => (size.width - width) / 2,
    };
    final top = math.max(0.0, (size.height - height) / 2);

    final paint = Paint()
      // 这一行是整个效果的关键：关掉插值，放大后每个像素都是硬边方块。
      ..filterQuality = FilterQuality.none
      ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(left, top, width, height),
      paint,
    );
  }

  void _paintFallback(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: kPixelLyricGridSize * kPixelLyricScale * scale,
          fontWeight: fontWeight,
        ),
      ),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width);
    painter.paint(
      canvas,
      Offset(0, math.max(0.0, (size.height - painter.height) / 2)),
    );
  }

  @override
  bool shouldRepaint(covariant PixelLyricPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.color != color ||
        oldDelegate.fontWeight != fontWeight ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.scale != scale;
  }
}

/// 一行像素歌词（无进度）。
///
/// 用 [CustomPaint] 而不是 `Image` widget：栅格图按行缓存，`CustomPaint` 能在
/// 不重建 widget 树的前提下换色（远处行渐隐、当前行变主题色）。
class PixelLyricText extends StatelessWidget {
  const PixelLyricText({
    super.key,
    required this.text,
    required this.color,
    this.fontWeight = FontWeight.bold,
    this.textAlign = TextAlign.center,
    this.scale = 1,
  });

  final String text;
  final Color color;
  final FontWeight fontWeight;
  final TextAlign textAlign;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: pixelLyricLineHeight(scale),
      child: CustomPaint(
        painter: PixelLyricPainter(
          text: text,
          color: color,
          fontWeight: fontWeight,
          textAlign: textAlign,
          scale: scale,
        ),
      ),
    );
  }
}

/// 带卡拉 OK 进度的一行像素歌词。
///
/// 底层是未唱色的整行，上层是已唱色的同一个字，按 [fill] 从左侧裁开——和
/// [_PartialKtvWord] 一个思路，只是作用在整行而不是单个字。像素图逐字裁剪会
/// 让每个字的栅格互不对齐（每个词的宽度不同），整行裁才是连续的。
class PixelLyricFillText extends StatelessWidget {
  const PixelLyricFillText({
    super.key,
    required this.text,
    required this.fill,
    required this.activeColor,
    required this.dimColor,
    this.fontWeight = FontWeight.bold,
    this.textAlign = TextAlign.center,
    this.scale = 1,
  });

  final String text;

  /// 已唱比例 0~1。
  final double fill;
  final Color activeColor;
  final Color dimColor;
  final FontWeight fontWeight;
  final TextAlign textAlign;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final height = pixelLyricLineHeight(scale);
    if (fill <= 0) {
      return SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(
          painter: PixelLyricPainter(
            text: text,
            color: dimColor,
            fontWeight: fontWeight,
            textAlign: textAlign,
            scale: scale,
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: PixelLyricPainter(
              text: text,
              color: dimColor,
              fontWeight: fontWeight,
              textAlign: textAlign,
              scale: scale,
            ),
          ),
          if (fill < 1)
            ClipRect(
              clipper: _PixelFillClipper(fill),
              child: CustomPaint(
                size: Size.infinite,
                painter: PixelLyricPainter(
                  text: text,
                  color: activeColor,
                  fontWeight: fontWeight,
                  textAlign: textAlign,
                  scale: scale,
                ),
              ),
            )
          else
            CustomPaint(
              size: Size.infinite,
              painter: PixelLyricPainter(
                text: text,
                color: activeColor,
                fontWeight: fontWeight,
                textAlign: textAlign,
                scale: scale,
              ),
            ),
        ],
      ),
    );
  }
}

class _PixelFillClipper extends CustomClipper<Rect> {
  const _PixelFillClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) {
    // 按栅格像素对齐裁剪：不对齐的话已唱边缘会出现半个像素的抖动，
    // 与点阵的硬边质感冲突。
    final cell = kPixelLyricScale;
    final raw = size.width * fraction.clamp(0.0, 1.0);
    final snapped = (raw / cell).round() * cell;
    return Rect.fromLTWH(0, 0, snapped, size.height);
  }

  @override
  bool shouldReclip(covariant _PixelFillClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
