import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/lyric/presentation/lyric_effects.dart';

void main() {
  group('模糊半径', () {
    test('当前行永远是 0，滑杆拖满也不糊', () {
      for (final amount in [0.0, 0.3, 0.6, 1.0]) {
        expect(lyricBlurSigmaFor(distance: 0, amount: amount), 0);
      }
    });

    test('档位为 0 时整屏都不糊', () {
      for (var distance = 0; distance <= 6; distance++) {
        expect(lyricBlurSigmaFor(distance: distance, amount: 0), 0);
      }
    });

    test('越远越糊，到第 3 行封顶', () {
      double sigma(int d) => lyricBlurSigmaFor(distance: d, amount: 1);
      expect(sigma(1), greaterThan(0));
      expect(sigma(2), greaterThan(sigma(1)));
      expect(sigma(3), greaterThan(sigma(2)));
      // 更远的行本来就快滚出视口，继续加模糊只是白花 GPU。
      expect(sigma(4), sigma(3));
      expect(sigma(9), sigma(3));
    });

    test('档位与半径线性，0.5 就是最大值的一半', () {
      final full = lyricBlurSigmaFor(distance: 3, amount: 1);
      expect(full, closeTo(kLyricMaxBlurSigma, 1e-9));
      expect(
        lyricBlurSigmaFor(distance: 3, amount: 0.5),
        closeTo(full / 2, 1e-9),
      );
    });

    test('负数距离（不该出现）当作当前行', () {
      expect(lyricBlurSigmaFor(distance: -1, amount: 1), 0);
    });
  });

  group('模糊包装', () {
    testWidgets('半径接近 0 时不额外套一层', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: lyricBlurredProbe(sigma: 0)),
      );
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('有半径时套上 ImageFiltered', (tester) async {
      await tester.pumpWidget(MaterialApp(home: lyricBlurredProbe(sigma: 2.5)));
      expect(find.byType(ImageFiltered), findsOneWidget);
    });
  });

  group('入场动画', () {
    testWidgets('首帧就是终态，进页面不会再多淡一次', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LyricEntrance(
            style: LyricEntranceStyle.fade,
            playKey: 'a',
            child: Text('词'),
          ),
        ),
      );
      // 不等任何动画：页面转场已经播过一次，这里再淡入会像加载了两次。
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        closeTo(1, 1e-6),
      );
    });

    testWidgets('换 playKey 才重放', (tester) async {
      Widget host(String key) => MaterialApp(
        home: LyricEntrance(
          style: LyricEntranceStyle.fade,
          playKey: key,
          child: const Text('词'),
        ),
      );

      await tester.pumpWidget(host('song-1'));
      await tester.pumpAndSettle();

      // 同一个 key 的重建不该让歌词再淡进来一次。
      await tester.pumpWidget(host('song-1'));
      await tester.pump();
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        closeTo(1, 1e-6),
      );

      await tester.pumpWidget(host('song-2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, lessThan(1));
    });

    testWidgets('上滑是「一边上移一边淡入」', (tester) async {
      Widget host(String key) => MaterialApp(
        home: LyricEntrance(
          style: LyricEntranceStyle.slideUp,
          playKey: key,
          child: const Text('词'),
        ),
      );

      await tester.pumpWidget(host('a'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host('b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final transform = tester.widget<Transform>(find.byType(Transform));
      // 起点在下方，正在往上走。
      expect(transform.transform.getTranslation().y, greaterThan(0));
    });

    testWidgets('playOnMount 挂载即播——换歌经过加载态后动画不会丢', (tester) async {
      // 换歌一定会先显示「正在加载歌词」，那段时间 LyricEntrance 被整个摘出
      // 树，回来时是新 State，playKey 那条路径永远走不到。这条用例锁住它。
      await tester.pumpWidget(
        const MaterialApp(
          home: LyricEntrance(
            style: LyricEntranceStyle.fade,
            playKey: 'song-1',
            playOnMount: true,
            child: Text('词'),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        lessThan(0.5),
        reason: '挂载后应从头开始，而不是直接终态',
      );

      await tester.pumpAndSettle();
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        closeTo(1, 1e-6),
      );
    });

    testWidgets('playOnMount 时减少动效直接给终态', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: LyricEntrance(
              style: LyricEntranceStyle.fade,
              playKey: 'song-1',
              playOnMount: true,
              child: Text('词'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        closeTo(1, 1e-6),
      );
    });
  });
}

/// 测试用的最小宿主：只关心「有没有套 ImageFiltered」。
class lyricBlurredProbe extends StatelessWidget {
  const lyricBlurredProbe({super.key, required this.sigma});

  final double sigma;

  @override
  Widget build(BuildContext context) {
    return Center(child: lyricBlurred(const Text('内容'), sigma));
  }
}
