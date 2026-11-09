import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/lyric/presentation/lyric_share_card.dart';

/// 分享卡片会被导出成 PNG，画错之后用户保存下来的图是修不回来的。
/// 这里钉住两类最容易悄悄回归的问题。

Widget _host({
  required bool dark,
  String? artwork,
  TextStyle? inheritedStyle,
}) {
  final card = LyricShareCard(
    title: '回到过去',
    artist: '周杰伦',
    line: '想回到过去',
    previous: '还来不来得及',
    next: '思绪不断',
    dark: dark,
    appName: 'Koyze',
    artwork: artwork,
  );
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1DB954)),
    ),
    home: Scaffold(
      body: Center(
        child: inheritedStyle == null
            ? card
            : DefaultTextStyle(style: inheritedStyle, child: card),
      ),
    ),
  );
}

void main() {
  testWidgets('卡片上的文字不带任何装饰线', (tester) async {
    await tester.pumpWidget(_host(dark: false));

    final texts = tester.widgetList<RichText>(find.byType(RichText)).toList();
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(
        text.text.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: '分享卡片的文字不能带装饰线：${text.text.toPlainText()}',
      );
    }
  });

  testWidgets('外层的下划线不会渗进卡片', (tester) async {
    // 这条是真正的回归点：Text 会把自身样式 merge 到上层 DefaultTextStyle，
    // 只要祖先带了下划线，卡片每一行都会被画上一条线（曾出现过黄色双线）。
    await tester.pumpWidget(
      _host(
        dark: false,
        inheritedStyle: const TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.double,
          decorationColor: Color(0xFFFFEB3B),
        ),
      ),
    );

    final texts = tester.widgetList<RichText>(find.byType(RichText)).toList();
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(
        text.text.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: '外层下划线渗进了：${text.text.toPlainText()}',
      );
    }
  });

  testWidgets('深色卡片同样不继承装饰线', (tester) async {
    await tester.pumpWidget(
      _host(
        dark: true,
        inheritedStyle: const TextStyle(
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFFFFEB3B),
        ),
      ),
    );

    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      expect(
        text.text.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: '深色卡片出现了装饰线：${text.text.toPlainText()}',
      );
    }
  });

  testWidgets('没有封面时不留下空洞', (tester) async {
    await tester.pumpWidget(_host(dark: false));
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
  });

  testWidgets('三段歌词与曲目信息都在卡片里', (tester) async {
    await tester.pumpWidget(_host(dark: false));
    expect(find.text('想回到过去'), findsOneWidget);
    expect(find.text('还来不来得及'), findsOneWidget);
    expect(find.text('思绪不断'), findsOneWidget);
    expect(find.text('回到过去'), findsOneWidget);
    expect(find.text('周杰伦'), findsOneWidget);
    expect(find.text('KOYZE'), findsOneWidget);
  });
}
