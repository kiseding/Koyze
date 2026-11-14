import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/artwork_image.dart';

/// 封面在路由入场动效期间不该发起加载：首屏十几张一起开图会把连接和解码
/// 全压进动效那几帧。占位先顶上，动效播完再换成真图。
void main() {
  test('默认对入场动效推迟封面，所有歌曲列表共用一套行为', () {
    const image = ArtworkImage('https://example.com/cover.jpg');
    expect(image.deferDuringEntrance, isTrue);
    expect(image.placeholder, isNull, reason: '默认占位是中性底色 + 音符');
  });

  Widget app({required bool defer}) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: ArtworkImage(
                          'https://example.com/cover.jpg',
                          cacheWidth: 96,
                          deferDuringEntrance: defer,
                          errorBuilder: (_, __, ___) => const Text('failed'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('入场动效期间先显示占位封面，播完才建 Image', (tester) async {
    await tester.pumpWidget(app(defer: true));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);
  });

  testWidgets('deferDuringEntrance: false 时立刻建 Image', (tester) async {
    await tester.pumpWidget(app(defer: false));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(Image), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('不在路由里时立刻建 Image', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: ArtworkImage(
                'https://example.com/cover.jpg',
                cacheWidth: 96,
                errorBuilder: (_, __, ___) => const Text('failed'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });
}
