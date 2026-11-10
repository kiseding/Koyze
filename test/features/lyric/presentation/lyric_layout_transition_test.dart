import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/audio_handler.dart';
import 'package:koyze/features/lyric/domain/lyric.dart';
import 'package:koyze/features/lyric/presentation/compact_lyric_view.dart';
import 'package:koyze/features/lyric/presentation/lyric_provider.dart';
import 'package:koyze/features/lyric/presentation/lyric_view.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';

/// 只暴露固定状态的 LyricNotifier，避免测试触发真实的歌词请求。
class _StubLyricNotifier extends LyricNotifier {
  _StubLyricNotifier(LyricLoadState initial)
    : super((_) async => Lyrics.empty()) {
    publish(initial);
  }

  @override
  Future<void> select(MusicItem? music) async {}
}

class _FixedPositionNotifier extends PositionNotifier {
  _FixedPositionNotifier(Duration initial) : super(null) {
    update(initial);
  }
}

/// 最近的 DefaultTextStyle 样式。歌词文字的样式在祖先链上，不在 Text 自己身上。
TextStyle? _inheritedStyle(WidgetTester tester, String text) {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) return null;
  TextStyle? style;
  finder.evaluate().first.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is AnimatedDefaultTextStyle) {
      style = widget.style;
      return false;
    }
    if (widget is DefaultTextStyle) {
      style = widget.style;
      return false;
    }
    return true;
  });
  return style;
}

double? _inheritedFontSize(WidgetTester tester, String text) =>
    _inheritedStyle(tester, text)?.fontSize;

/// 单行视图里当前在场的透明度层：换行过渡中会同时有新旧两层。
List<double> _lineOpacities(WidgetTester tester) => tester
    .widgetList<Opacity>(
      find.descendant(
        of: find.byType(CompactLyricView),
        matching: find.byType(Opacity),
      ),
    )
    .map((widget) => widget.opacity)
    .toList();

void main() {
  const accent = Color(0xFF1DB954);

  setUp(() {
    audioHandler = BaseAudioHandler();
  });

  Lyrics withLongGap() => const Lyrics(
    raw: '',
    lines: [
      // 第一句到第二句隔了 6 秒，会触发间奏点（>3.8s）。
      LyricLine(time: Duration.zero, text: '第一句'),
      LyricLine(time: Duration(seconds: 6), text: '第二句'),
      LyricLine(time: Duration(seconds: 12), text: '第三句'),
    ],
  );

  Lyrics withWordTiming() => Lyrics(
    raw: '',
    lines: [
      const LyricLine(time: Duration.zero, text: '第一句'),
      LyricLine(
        time: const Duration(seconds: 5),
        text: '第二句',
        words: const [
          LyricWord(time: Duration(seconds: 5), text: '第'),
          LyricWord(time: Duration(seconds: 6), text: '二'),
          LyricWord(time: Duration(seconds: 7), text: '句'),
        ],
      ),
    ],
  );

  Widget scrollHarness({
    required Lyrics lyrics,
    required int currentLine,
    String? fontFamily,
  }) {
    return ProviderScope(
      overrides: [
        currentLyricLoadProvider.overrideWith(
          () => _StubLyricNotifier(LyricLoadState(lyrics: lyrics)),
        ),
        currentMusicProvider.overrideWithValue(
          MusicItem(
            id: 't1',
            name: '歌',
            singer: '手',
            duration: const Duration(seconds: 200),
            source: 'local',
          ),
        ),
        seekProvider.overrideWithValue((duration) async {}),
        playerPositionProvider.overrideWith(
          () => _FixedPositionNotifier(const Duration(seconds: 7)),
        ),
        currentLineIndexProvider.overrideWithValue(currentLine),
      ],
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: fontFamily,
          colorScheme: ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: const LyricView(isFullScreen: true),
          ),
        ),
      ),
    );
  }

  Widget compactHarness({
    required Lyrics lyrics,
    required int index,
    LyricLayout layout = LyricLayout.singleLine,
    Alignment align = Alignment.center,
    SingleLineAnimation animation = SingleLineAnimation.fade,
    String? fontFamily,
  }) {
    return ProviderScope(
      overrides: [
        currentLyricProvider.overrideWithValue(lyrics),
        currentLineIndexProvider.overrideWithValue(index),
      ],
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: fontFamily,
          colorScheme: ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: CompactLyricView(
              layout: layout,
              animation: animation,
              align: align,
            ),
          ),
        ),
      ),
    );
  }

  group('滚动列表', () {
    testWidgets('进出长间奏不会重建列表，滚动位置不会闪回', (tester) async {
      await tester.pumpWidget(
        scrollHarness(lyrics: withLongGap(), currentLine: 0),
      );
      await tester.pumpAndSettle();
      // 第一句后面有 6 秒空档，这一帧一定叠着间奏点那一层。
      final before = tester.element(find.byType(ListView));

      await tester.pumpWidget(
        scrollHarness(lyrics: withLongGap(), currentLine: 1),
      );
      await tester.pumpAndSettle();

      // 树结构一变，ListView 就会被摘下来重建，offset 会有一帧归零——
      // 那正是用户看到的"闪一下"。这里断言 element 自始至终是同一个。
      expect(identical(tester.element(find.byType(ListView)), before), isTrue);
    });

    testWidgets('切到逐字行时，逐字歌词跟着字号一起过渡而不是直接跳到终值', (tester) async {
      await tester.pumpWidget(
        scrollHarness(lyrics: withWordTiming(), currentLine: 0),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        scrollHarness(lyrics: withWordTiming(), currentLine: 1),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final size = _inheritedFontSize(tester, '第');
      expect(size, isNotNull, reason: '逐字行应该已经渲染出来');
      // 从 16 往 20 过渡的中途。旧实现给 KTV 传的是写死的 20，这里会直接等于 20，
      // 于是换行的那一帧字号"啪"地跳一档，看起来就是闪。
      expect(size, greaterThan(16));
      expect(size, lessThan(19.9));
    });

    testWidgets('整行动画样式不会丢掉主题字体族', (tester) async {
      await tester.pumpWidget(
        scrollHarness(
          lyrics: withLongGap(),
          currentLine: 0,
          fontFamily: 'KoyzeTestFont',
        ),
      );
      await tester.pumpAndSettle();

      // AnimatedDefaultTextStyle 是整体替换而不是合并；给裸 TextStyle 就会把
      // fontFamily 抹成 null，点阵歌词按继承样式取字体时只能栅格化成方块。
      expect(_inheritedStyle(tester, '第一句')?.fontFamily, 'KoyzeTestFont');
    });
  });

  group('单行模式', () {
    testWidgets('换行时新旧两行同时在场，不会有一帧空白', (tester) async {
      final lyrics = withLongGap();
      await tester.pumpWidget(compactHarness(lyrics: lyrics, index: 0));
      await tester.pumpAndSettle();

      await tester.pumpWidget(compactHarness(lyrics: lyrics, index: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 交叉过渡：旧行还在淡出，新行已经开始淡入。
      expect(find.text('第一句'), findsOneWidget);
      expect(find.text('第二句'), findsOneWidget);
    });

    testWidgets('旧行比新行退得快，中段不会两句话糊在一起', (tester) async {
      final lyrics = withLongGap();
      await tester.pumpWidget(compactHarness(lyrics: lyrics, index: 0));
      await tester.pumpAndSettle();

      await tester.pumpWidget(compactHarness(lyrics: lyrics, index: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 112));

      final opacities = _lineOpacities(tester);
      expect(opacities.length, 2, reason: '过渡中应该新旧两层同时在场');
      opacities.sort();
      // 旧行按 1.6 倍速退场：40% 时已经几乎看不见。早先两行用同一条缓动曲线，
      // 中段两边都还有九成不透明，两句话叠在同一处，看起来就是一团重影。
      expect(opacities.first, lessThan(0.15));
      expect(opacities.last, greaterThan(0.6));
    });

    testWidgets('同一行重建不会重放入场动画', (tester) async {
      final lyrics = withLongGap();
      await tester.pumpWidget(compactHarness(lyrics: lyrics, index: 0));
      await tester.pumpAndSettle();
      expect(_lineOpacities(tester), [1.0]);

      // 与换行无关的重建（父级刷新、设置变更）：不该再淡入一遍。
      await tester.pumpWidget(compactHarness(lyrics: lyrics, index: 0));
      await tester.pump();

      expect(_lineOpacities(tester), [1.0]);
    });

    testWidgets('居中对齐时文字本身也居中', (tester) async {
      await tester.pumpWidget(compactHarness(lyrics: withLongGap(), index: 0));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('第一句'));
      expect(text.textAlign, TextAlign.center);
    });

    testWidgets('左对齐时文字跟随', (tester) async {
      await tester.pumpWidget(
        compactHarness(
          lyrics: withLongGap(),
          index: 0,
          align: Alignment.centerLeft,
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('第一句'));
      expect(text.textAlign, TextAlign.start);
    });

    testWidgets('翻译与音译只在有内容时出现', (tester) async {
      final lyrics = Lyrics(
        raw: '',
        lines: [
          const LyricLine(
            time: Duration.zero,
            text: '原文',
            roman: 'romaji',
            translation: '译文',
          ),
          const LyricLine(time: Duration(seconds: 6), text: '第二句'),
        ],
      );
      await tester.pumpWidget(compactHarness(lyrics: lyrics, index: 0));
      await tester.pumpAndSettle();

      expect(find.text('romaji'), findsOneWidget);
      expect(find.text('译文'), findsOneWidget);
    });
  });

  group('轮盘模式', () {
    testWidgets('当前行比邻近行大，且用字号撑开而不是缩放', (tester) async {
      final lyrics = Lyrics(
        raw: '',
        lines: [
          for (var i = 0; i < 5; i++)
            LyricLine(
              time: Duration(seconds: i * 5),
              text: '第$i句',
            ),
        ],
      );
      await tester.pumpWidget(
        compactHarness(lyrics: lyrics, index: 2, layout: LyricLayout.roulette),
      );
      await tester.pumpAndSettle();

      final current = _inheritedFontSize(tester, '第2句');
      final neighbor = _inheritedFontSize(tester, '第1句');
      final far = _inheritedFontSize(tester, '第0句');

      expect(current, greaterThan(neighbor!));
      expect(neighbor, greaterThan(far!));
      // 缩放不再参与排版：聊天记录里"越远空档越大"就是因为 Transform.scale
      // 只缩放画面、不缩放占位。这里断言层级是字号决定的。
      expect(
        find.descendant(
          of: find.byType(CompactLyricView),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    });

    testWidgets('轮盘各行沿用主题字体族', (tester) async {
      final lyrics = Lyrics(
        raw: '',
        lines: [
          for (var i = 0; i < 5; i++)
            LyricLine(
              time: Duration(seconds: i * 5),
              text: '第$i句',
            ),
        ],
      );
      await tester.pumpWidget(
        compactHarness(
          lyrics: lyrics,
          index: 2,
          layout: LyricLayout.roulette,
          fontFamily: 'KoyzeTestFont',
        ),
      );
      await tester.pumpAndSettle();

      expect(_inheritedStyle(tester, '第2句')?.fontFamily, 'KoyzeTestFont');
      expect(_inheritedStyle(tester, '第1句')?.fontFamily, 'KoyzeTestFont');
    });

    testWidgets('超出首尾的行不渲染', (tester) async {
      final lyrics = Lyrics(
        raw: '',
        lines: [
          for (var i = 0; i < 3; i++)
            LyricLine(
              time: Duration(seconds: i * 5),
              text: '第$i句',
            ),
        ],
      );
      await tester.pumpWidget(
        compactHarness(lyrics: lyrics, index: 0, layout: LyricLayout.roulette),
      );
      await tester.pumpAndSettle();

      // index=0 时只有 0/1/2 三行，不该出现越界的下标。
      expect(tester.takeException(), isNull);
      expect(find.text('第0句'), findsOneWidget);
      expect(find.text('第2句'), findsOneWidget);
    });
  });
}
