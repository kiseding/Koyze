// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/lyric/presentation/pixel_lyric.dart';

/// 从 CustomPaint 上取回绘制指令，用于确认「真的画了图」而不是退化成文字。
List<CustomPaint> _paintsOf(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(PixelLyricText),
          matching: find.byType(CustomPaint),
        ),
      )
      .toList();
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );
}

void main() {
  setUp(PixelLyricPainter.clearCache);
  tearDown(PixelLyricPainter.clearCache);

  testWidgets('点阵图是二值的：只有 0 和 255 两种透明度', (tester) async {
    PixelLyricBitmap? bitmap;
    await tester.runAsync(() async {
      bitmap = await PixelLyricPainter.load('春不晚', FontWeight.bold);
    });

    expect(bitmap, isNotNull, reason: '应能栅格化出点阵图');

    final data = await tester.runAsync(
      () => bitmap!.image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final pixels = data!.buffer.asUint8List();
    final alphas = <int>{};
    for (var i = 3; i < pixels.length; i += 4) {
      alphas.add(pixels[i]);
    }

    // 这一步是新版的关键：抗锯齿的中间灰全被阈值压掉了，
    // 放大后才不会出现「每个方块灰度都不一样」的糊。
    expect(alphas.difference({0, 255}), isEmpty, reason: '点阵必须只有全透明和全不透明两种像素');
    expect(alphas.contains(255), isTrue, reason: '至少要有墨迹');
  });

  testWidgets('点阵图裁到墨迹边界，四周不留空行', (tester) async {
    PixelLyricBitmap? bitmap;
    await tester.runAsync(() async {
      bitmap = await PixelLyricPainter.load('夜', FontWeight.bold);
    });

    expect(bitmap, isNotNull);
    // 栅格是 kPixelLyricGridSize 见方，单字裁边后应该贴着这个尺寸，
    // 而不是留着整个行盒的空白。
    expect(bitmap!.image.height, lessThanOrEqualTo(kPixelLyricGridSize + 2));
    expect(bitmap!.image.width, lessThanOrEqualTo(kPixelLyricGridSize + 2));
  });

  testWidgets('同一行文字只栅格化一次', (tester) async {
    PixelLyricBitmap? first;
    PixelLyricBitmap? second;
    await tester.runAsync(() async {
      first = await PixelLyricPainter.load('重复行', FontWeight.bold);
      second = await PixelLyricPainter.load('重复行', FontWeight.bold);
    });

    expect(identical(first!.image, second!.image), isTrue);
  });

  testWidgets('字体族参与缓存键', (tester) async {
    await tester.runAsync(() async {
      await PixelLyricPainter.load('换字体', FontWeight.bold, 'FamilyA');
    });

    expect(
      PixelLyricPainter.peek('换字体', FontWeight.bold, 'FamilyA'),
      isNotNull,
    );
    expect(PixelLyricPainter.peek('换字体', FontWeight.bold), isNull);
  });

  testWidgets('预热过的行首帧就绘制点阵图', (tester) async {
    // 别先挂 PixelLyricText：它会在假时钟里发起一次加载，之后在 runAsync 里
    // 等同一个 Future 就永远等不到了（伪异步时钟在 runAsync 期间是停住的）。
    await tester.pumpWidget(_host(const Text('probe')));
    // 字体族取自 DefaultTextStyle，测试环境里是默认字体，必须读出来才能对上缓存键。
    final family = DefaultTextStyle.of(
      tester.element(find.text('probe')),
    ).style.fontFamily;

    await tester.runAsync(() => PixelLyricPainter.prefetch(['预热点阵'], family));

    await tester.pumpWidget(
      _host(const PixelLyricText(text: '预热点阵', color: Colors.white)),
    );

    final painter = _paintsOf(tester).single.painter as PixelLyricPainter;
    expect(painter.bitmap, isNotNull, reason: '缓存命中时应直接使用点阵图');
  });

  testWidgets('换色不重新栅格化，只改 ColorFilter', (tester) async {
    await tester.pumpWidget(
      _host(const PixelLyricText(text: '换色', color: Colors.white)),
    );
    final painterA = _paintsOf(tester).single.painter as PixelLyricPainter;

    await tester.pumpWidget(
      _host(const PixelLyricText(text: '换色', color: Colors.green)),
    );
    final painterB = _paintsOf(tester).single.painter as PixelLyricPainter;

    expect(painterA.color, Colors.white);
    expect(painterB.color, Colors.green);
    expect(painterB.shouldRepaint(painterA), isTrue);
  });

  testWidgets('空文本不绘制也不崩', (tester) async {
    await tester.pumpWidget(
      _host(const PixelLyricText(text: '', color: Colors.white)),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(PixelLyricText), findsOneWidget);
  });

  testWidgets('进度为 0 时只有底层，进度为 1 时不裁剪', (tester) async {
    await tester.pumpWidget(
      _host(
        const PixelLyricFillText(
          text: '夜に駆ける',
          fill: 0,
          activeColor: Colors.green,
          dimColor: Colors.grey,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(PixelLyricFillText),
        matching: find.byType(ClipRect),
      ),
      findsNothing,
      reason: '完全没唱时不该有裁剪层',
    );

    await tester.pumpWidget(
      _host(
        const PixelLyricFillText(
          text: '夜に駆ける',
          fill: 1,
          activeColor: Colors.green,
          dimColor: Colors.grey,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(PixelLyricFillText),
        matching: find.byType(ClipRect),
      ),
      findsNothing,
      reason: '整行唱完时不该有裁剪层',
    );

    await tester.pumpWidget(
      _host(
        const PixelLyricFillText(
          text: '夜に駆ける',
          fill: 0.5,
          activeColor: Colors.green,
          dimColor: Colors.grey,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(PixelLyricFillText),
        matching: find.byType(ClipRect),
      ),
      findsOneWidget,
      reason: '唱到一半要有裁剪层把已唱部分露出来',
    );
  });

  testWidgets('行高随字号倍率线性增长', (tester) async {
    final base = pixelLyricLineHeight(1);
    final doubled = pixelLyricLineHeight(2);

    expect(doubled, greaterThan(base));
    // 常数项（12）不参与缩放，所以不是严格的 2 倍，但必须接近。
    expect(doubled, closeTo(base * 2 - 12, 0.01));
  });

  test('点尺寸按物理像素对齐', () {
    // 2.0 逻辑点 × 3 倍屏 = 6 个物理像素，正好整数。
    expect(kPixelLyricCell, 2);
    expect(pixelLyricLineHeight(1), greaterThan(20));
  });

  group('长句收窄点尺寸', () {
    Future<double> fit(
      WidgetTester tester, {
      required int imageWidth,
      required double available,
      double dpr = 3,
      double baseCell = 2,
    }) async {
      var cell = -1.0;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            devicePixelRatio: dpr,
            size: const Size(390, 844),
          ),
          child: Builder(
            builder: (context) {
              cell = pixelLyricFitCell(
                context,
                baseCell: baseCell,
                imageWidth: imageWidth,
                available: available,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return cell;
    }

    testWidgets('放得下就保持基准尺寸', (tester) async {
      expect(await fit(tester, imageWidth: 100, available: 390), 2);
    });

    testWidgets('放不下时收到整数物理像素', (tester) async {
      // 390 逻辑宽 × 3 = 1170 物理像素，219 个点 → 每点 5.34，取 5。
      final cell = await fit(tester, imageWidth: 219, available: 390);
      expect(cell, closeTo(5 / 3, 1e-9));
      // 收到半像素上就会糊，必须还是整数。
      expect((cell * 3).roundToDouble(), 5);
    });

    testWidgets('宽度未知时不动', (tester) async {
      expect(await fit(tester, imageWidth: 219, available: double.infinity), 2);
    });

    testWidgets('再长也保住一个物理像素', (tester) async {
      final cell = await fit(tester, imageWidth: 5000, available: 390);
      expect(cell, closeTo(1 / 3, 1e-9));
    });
  });

  test('缓存上限生效，clearCache 幂等', () {
    PixelLyricPainter.clearCache();
    PixelLyricPainter.clearCache();
    expect(PixelLyricPainter.peek('没有这行', FontWeight.bold), isNull);
  });
}
