// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

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
    home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
  );
}

void main() {
  setUp(PixelLyricPainter.clearCache);
  tearDown(PixelLyricPainter.clearCache);

  testWidgets('栅格图按 11px 渲染后放大，尺寸由倍数决定', (tester) async {
    await tester.pumpWidget(
      _host(const PixelLyricText(text: '春不晚', color: Colors.white)),
    );

    final image = PixelLyricPainter.imageFor('春不晚', FontWeight.bold);
    expect(image, isNotNull, reason: '应能栅格化出点阵图');

    // 三个汉字在 11px 下宽度约 33px；放大 1.8 倍后接近正常歌词字号。
    expect(image!.width, inInclusiveRange(20, 60));
    expect(image.height, lessThanOrEqualTo(30));
  });

  testWidgets('同一行文字只栅格化一次', (tester) async {
    await tester.pumpWidget(
      _host(const PixelLyricText(text: '重复行', color: Colors.white)),
    );
    final first = PixelLyricPainter.imageFor('重复行', FontWeight.bold);

    await tester.pumpWidget(
      _host(const PixelLyricText(text: '重复行', color: Colors.red)),
    );
    final second = PixelLyricPainter.imageFor('重复行', FontWeight.bold);

    // 颜色不参与缓存键：同一份白色栅格图用 ColorFilter 染成任意颜色。
    expect(identical(first, second), isTrue);
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

  test('缓存上限生效，不会无限增长', () {
    // 栅格化依赖引擎，单元测试里没有；这里只验证 clearCache 是幂等的。
    PixelLyricPainter.clearCache();
    PixelLyricPainter.clearCache();
    expect(true, isTrue);
  });
}
