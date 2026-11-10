// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 像素歌词的栅格字号。
///
/// 这个值就是「一行字有多少个点」的上限：汉字在这个字号下大约 16 个点高。
/// 12 个点时笔画多的字（像、要、融）会粘成黑块；再往上字号够了，但一行
/// 装不下十几个汉字——宽度不够时由 [pixelLyricFitCell] 把点收小。
const double kPixelLyricGridSize = 16;

/// 一个点绘制出来的逻辑尺寸。
///
/// 必须让「栅格像素 : 屏幕像素」接近整数，否则最近邻放大会让同一条笔画里
/// 出现 1 点和 2 点宽的方块，看着就是残缺的。实际绘制时还会按设备像素比
/// 再对齐一次，见 [pixelLyricCellFor]。
const double kPixelLyricCell = 2;

/// 一行像素歌词的绘制高度。
double pixelLyricLineHeight(double scale) =>
    kPixelLyricGridSize * kPixelLyricCell * 1.2 * scale + 12;

/// 按设备像素比把点尺寸对齐到整数物理像素。
///
/// 不对齐的话，2.0 逻辑点 × 2.75 倍屏 = 5.5 个物理像素，相邻点会一半 5 像素、
/// 一半 6 像素，点阵立刻显得脏。
double pixelLyricCellFor(BuildContext context, double scale) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  if (dpr <= 0) return kPixelLyricCell * scale;
  final snapped = (kPixelLyricCell * scale * dpr).roundToDouble();
  return snapped.clamp(1.0, 4096.0) / dpr;
}

/// 一行太长、按基准点尺寸放不下时，把点收小到刚好铺满可用宽度。
///
/// 收小仍然落在整数物理像素上：点尺寸一旦是半像素，最近邻放大就会出现
/// 忽宽忽窄的方块，比整体小一号更难看。真放不下（可用宽度连一个物理像素
/// 都不够）就退回基准尺寸，交给裁剪层处理。
double pixelLyricFitCell(
  BuildContext context, {
  required double baseCell,
  required int imageWidth,
  required double available,
}) {
  if (imageWidth <= 0 || available <= 0 || !available.isFinite) return baseCell;
  if (imageWidth * baseCell <= available) return baseCell;
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  if (dpr <= 0) return available / imageWidth;
  final physical = (available * dpr) / imageWidth;
  final snapped = physical.floorToDouble().clamp(1.0, 4096.0);
  return snapped / dpr;
}

/// 一张二值点阵图：每个像素就是一个点。
///
/// 点画多大由绘制时的可用宽度决定（见 [pixelLyricFitCell]），不跟着图走。
class PixelLyricBitmap {
  const PixelLyricBitmap({required this.image});

  final ui.Image image;
}

/// 把一行文字栅格化成真正的点阵图。
///
/// 和上一版的区别在「二值化」这一步：先用系统字体在 12px 下渲染，再读出
/// 像素、按阈值压成纯黑白，最后按点放大。之前是直接把 11px 的抗锯齿灰度图
/// 拉大 1.8 倍——每个方块灰度都不一样，堆在一起就是一团糊。
///
/// 栅格图一律画成白色，颜色在绘制时用 [ColorFilter] 染上去。这样「已唱」
/// 「未唱」两种颜色共用同一份点阵，缓存命中率翻倍。
class PixelLyricPainter extends CustomPainter {
  PixelLyricPainter({
    required this.text,
    required this.color,
    this.bitmap,
    this.fontFamily,
    this.fontWeight = FontWeight.bold,
    this.textAlign = TextAlign.center,
    this.cell = kPixelLyricCell,
  });

  final String text;
  final Color color;

  /// 已就绪的点阵图。为空时退回普通文字，绝不让整行消失。
  final PixelLyricBitmap? bitmap;

  /// 主题字体族。位图是离屏栅格化的，拿不到 DefaultTextStyle，必须显式传。
  final String? fontFamily;
  final FontWeight fontWeight;
  final TextAlign textAlign;
  final double cell;

  static final Map<String, Future<PixelLyricBitmap?>> _pending =
      <String, Future<PixelLyricBitmap?>>{};
  static final Map<String, PixelLyricBitmap> _ready =
      <String, PixelLyricBitmap>{};
  static const int _cacheLimit = 120;

  static String _key(String text, FontWeight weight, String? family) =>
      '$text|$weight|${family ?? ''}';

  /// 已经栅格化好的点阵图；没有则返回 null（不触发新的栅格化）。
  static PixelLyricBitmap? peek(
    String text,
    FontWeight fontWeight, [
    String? fontFamily,
  ]) {
    if (text.isEmpty) return null;
    return _ready[_key(text, fontWeight, fontFamily)];
  }

  /// 取（或生成）这一行文字的点阵图。
  ///
  /// 必须异步：二值化要读像素，而 `toByteData` 没有同步版本。调用方先用
  /// [peek] 拿缓存，miss 时再 await 这个 Future。
  static Future<PixelLyricBitmap?> load(
    String text,
    FontWeight fontWeight, [
    String? fontFamily,
  ]) {
    if (text.isEmpty) return Future<PixelLyricBitmap?>.value();
    final key = _key(text, fontWeight, fontFamily);
    final ready = _ready[key];
    if (ready != null) return Future<PixelLyricBitmap?>.value(ready);
    return _pending[key] ??= _build(text, fontWeight, fontFamily).then((
      bitmap,
    ) {
      _pending.remove(key);
      if (bitmap != null) {
        _ready[key] = bitmap;
        if (_ready.length > _cacheLimit) {
          final oldest = _ready.keys.first;
          _ready.remove(oldest)?.image.dispose();
        }
      }
      return bitmap;
    });
  }

  /// 整首歌预热。歌词一加载就把可见的几十行排成队，滚动时不会先看到普通字
  /// 再「啪」地变成点阵。
  static Future<void> prefetch(
    Iterable<String> lines, [
    String? fontFamily,
  ]) async {
    final seen = <String>{};
    for (final text in lines) {
      if (text.isEmpty || !seen.add(text)) continue;
      if (_ready.containsKey(_key(text, FontWeight.bold, fontFamily))) continue;
      await load(text, FontWeight.bold, fontFamily);
    }
  }

  /// 清空缓存。测试里换字体或改语言时会用；生产环境不需要。
  static void clearCache() {
    for (final bitmap in _ready.values) {
      bitmap.image.dispose();
    }
    _ready.clear();
    _pending.clear();
  }

  static ui.Paragraph _layout(
    String text,
    FontWeight fontWeight,
    String? fontFamily,
  ) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: fontFamily,
              fontSize: kPixelLyricGridSize,
              fontWeight: fontWeight,
              maxLines: 1,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: const Color(0xFFFFFFFF),
              fontFamily: fontFamily,
              fontSize: kPixelLyricGridSize,
              fontWeight: fontWeight,
            ),
          )
          ..addText(text);
    return builder.build()..layout(const ui.ParagraphConstraints(width: 16384));
  }

  static Future<PixelLyricBitmap?> _build(
    String text,
    FontWeight fontWeight,
    String? fontFamily,
  ) async {
    try {
      final paragraph = _layout(text, fontWeight, fontFamily);
      final width = paragraph.maxIntrinsicWidth.ceil().clamp(1, 4096);
      final height = paragraph.height.ceil().clamp(1, 256);

      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawParagraph(paragraph, Offset.zero);
      final picture = recorder.endRecording();
      final raw = picture.toImageSync(width, height);
      picture.dispose();

      final data = await raw.toByteData(format: ui.ImageByteFormat.rawRgba);
      raw.dispose();
      if (data == null) return null;

      final pixels = data.buffer.asUint8List();
      final ink = _binarize(pixels, width, height);
      if (ink == null) return null;

      final buffer = await ui.ImmutableBuffer.fromUint8List(ink.bytes);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: ink.width,
        height: ink.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      return PixelLyricBitmap(image: frame.image);
    } on Object {
      return null;
    }
  }

  /// 二值化 + 裁到墨迹边界。
  ///
  /// 裁边是必需的：12px 的行盒里有大量上下留白，不裁的话每行点阵都会离基线
  /// 很远，行距看起来忽大忽小。
  static ({Uint8List bytes, int width, int height})? _binarize(
    Uint8List rgba,
    int width,
    int height,
  ) {
    const threshold = 108; // 约 42% 不透明度
    var minX = width, minY = height, maxX = -1, maxY = -1;
    final mask = Uint8List(width * height);

    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (rgba[(row + x) * 4 + 3] < threshold) continue;
        mask[row + x] = 1;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (maxX < 0) return null;

    final w = maxX - minX + 1;
    final h = maxY - minY + 1;
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final srcRow = (y + minY) * width;
      final dstRow = y * w;
      for (var x = 0; x < w; x++) {
        if (mask[srcRow + x + minX] == 0) continue;
        final i = (dstRow + x) * 4;
        out[i] = 255;
        out[i + 1] = 255;
        out[i + 2] = 255;
        out[i + 3] = 255;
      }
    }
    return (bytes: out, width: w, height: h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final image = bitmap;
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
      cell: cell,
    );
  }

  /// 把点阵图放大画到 [size] 里。
  static void paintPixelImage(
    Canvas canvas,
    Size size,
    PixelLyricBitmap bitmap, {
    required Color color,
    required TextAlign textAlign,
    required double cell,
  }) {
    final width = bitmap.image.width * cell;
    final height = bitmap.image.height * cell;
    final left = switch (textAlign) {
      TextAlign.left || TextAlign.start => 0.0,
      TextAlign.right || TextAlign.end => size.width - width,
      _ => (size.width - width) / 2,
    };
    final top = math.max(0.0, (size.height - height) / 2);

    final paint = Paint()
      // 关键：关掉插值，放大后每个点都是硬边方块。
      ..filterQuality = FilterQuality.none
      ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
    canvas.drawImageRect(
      bitmap.image,
      Rect.fromLTWH(
        0,
        0,
        bitmap.image.width.toDouble(),
        bitmap.image.height.toDouble(),
      ),
      Rect.fromLTWH(left, top, width, height),
      paint,
    );
  }

  /// 点阵还没就绪时的占位。
  ///
  /// 必须自己算水平位置：`TextPainter.paint` 的 dx 是绝对坐标，[textAlign]
  /// 只在排版宽度大于文字宽度时才起作用，而这里排版宽度就是整行宽度，于是
  /// 居中会退化成贴左——首帧看到的是一行贴在屏幕左边缘、还可能被裁掉半截
  /// 的字，等点阵图回来再跳回中间。
  void _paintFallback(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontFamily: fontFamily,
          fontSize: kPixelLyricGridSize * cell,
          fontWeight: fontWeight,
        ),
      ),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width);
    final dx = switch (textAlign) {
      TextAlign.left || TextAlign.start => 0.0,
      TextAlign.right || TextAlign.end => size.width - painter.width,
      _ => (size.width - painter.width) / 2,
    };
    painter.paint(
      canvas,
      Offset(dx, math.max(0.0, (size.height - painter.height) / 2)),
    );
  }

  @override
  bool shouldRepaint(covariant PixelLyricPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.color != color ||
        oldDelegate.bitmap != bitmap ||
        oldDelegate.fontFamily != fontFamily ||
        oldDelegate.fontWeight != fontWeight ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.cell != cell;
  }
}

/// 负责「取点阵图 → 就绪后重建」的小外壳。
class _PixelBitmapHost extends StatefulWidget {
  const _PixelBitmapHost({
    required this.text,
    required this.fontWeight,
    required this.fontFamily,
    required this.builder,
  });

  final String text;
  final FontWeight fontWeight;
  final String? fontFamily;
  final Widget Function(BuildContext context, PixelLyricBitmap? bitmap) builder;

  @override
  State<_PixelBitmapHost> createState() => _PixelBitmapHostState();
}

class _PixelBitmapHostState extends State<_PixelBitmapHost> {
  PixelLyricBitmap? _bitmap;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _PixelBitmapHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.fontWeight != widget.fontWeight ||
        oldWidget.fontFamily != widget.fontFamily) {
      _resolve();
    }
  }

  void _resolve() {
    final cached = PixelLyricPainter.peek(
      widget.text,
      widget.fontWeight,
      widget.fontFamily,
    );
    _bitmap = cached;
    if (cached != null) return;
    final request = ++_request;
    PixelLyricPainter.load(
      widget.text,
      widget.fontWeight,
      widget.fontFamily,
    ).then((bitmap) {
      if (!mounted || request != _request) return;
      setState(() => _bitmap = bitmap);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _bitmap);
}

/// 一行像素歌词（无进度）。
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
    final cell = pixelLyricCellFor(context, scale);
    final family = DefaultTextStyle.of(context).style.fontFamily;
    return _PixelBitmapHost(
      text: text,
      fontWeight: fontWeight,
      fontFamily: family,
      builder: (context, bitmap) => SizedBox(
        width: double.infinity,
        height: pixelLyricLineHeight(scale),
        child: LayoutBuilder(
          builder: (context, constraints) => CustomPaint(
            painter: PixelLyricPainter(
              text: text,
              color: color,
              bitmap: bitmap,
              fontFamily: family,
              fontWeight: fontWeight,
              textAlign: textAlign,
              cell: pixelLyricFitCell(
                context,
                baseCell: cell,
                imageWidth: bitmap?.image.width ?? 0,
                available: constraints.maxWidth,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 带卡拉 OK 进度的一行像素歌词。
///
/// 底层是未唱色的整行，上层是已唱色的同一份点阵，按 [fill] 从左侧裁开。
/// 逐字裁剪会让每个字的点阵互不对齐，整行裁才是连续的。
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
    final cell = pixelLyricCellFor(context, scale);
    final family = DefaultTextStyle.of(context).style.fontFamily;
    final fraction = fill.clamp(0.0, 1.0);
    return _PixelBitmapHost(
      text: text,
      fontWeight: fontWeight,
      fontFamily: family,
      builder: (context, bitmap) {
        Widget layer(Color color, double usedCell) => CustomPaint(
          size: Size.infinite,
          painter: PixelLyricPainter(
            text: text,
            color: color,
            bitmap: bitmap,
            fontFamily: family,
            fontWeight: fontWeight,
            textAlign: textAlign,
            cell: usedCell,
          ),
        );
        return SizedBox(
          width: double.infinity,
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 两层和裁剪器必须用同一个点尺寸，否则已唱的绿色和未唱的白字
              // 会差半个点，边界上出现错位的毛边。
              final usedCell = pixelLyricFitCell(
                context,
                baseCell: cell,
                imageWidth: bitmap?.image.width ?? 0,
                available: constraints.maxWidth,
              );
              return fraction <= 0
                  ? layer(dimColor, usedCell)
                  : Stack(
                      children: [
                        layer(dimColor, usedCell),
                        if (fraction < 1)
                          ClipRect(
                            clipper: _PixelFillClipper(
                              fraction: fraction,
                              cell: usedCell,
                              imageWidth: bitmap?.image.width ?? 0,
                              textAlign: textAlign,
                            ),
                            child: layer(activeColor, usedCell),
                          )
                        else
                          layer(activeColor, usedCell),
                      ],
                    );
            },
          ),
        );
      },
    );
  }
}

class _PixelFillClipper extends CustomClipper<Rect> {
  const _PixelFillClipper({
    required this.fraction,
    required this.cell,
    required this.imageWidth,
    required this.textAlign,
  });

  final double fraction;
  final double cell;
  final int imageWidth;
  final TextAlign textAlign;

  @override
  Rect getClip(Size size) {
    // 已唱范围是「整行点阵宽度」的比例，不是容器宽度的比例：短句居中时两边
    // 各有几十像素空白，按容器算会让绿色慢半拍才开始、又提前唱完。
    final width = imageWidth * cell;
    final left = switch (textAlign) {
      TextAlign.left || TextAlign.start => 0.0,
      TextAlign.right || TextAlign.end => size.width - width,
      _ => (size.width - width) / 2,
    };
    // 按点对齐裁剪：不对齐的话已唱边缘会出现半个点的抖动。
    final snapped = (width * fraction / cell).round() * cell;
    return Rect.fromLTWH(0, 0, left + snapped, size.height);
  }

  @override
  bool shouldReclip(covariant _PixelFillClipper oldClipper) =>
      oldClipper.fraction != fraction ||
      oldClipper.cell != cell ||
      oldClipper.imageWidth != imageWidth ||
      oldClipper.textAlign != textAlign;
}
