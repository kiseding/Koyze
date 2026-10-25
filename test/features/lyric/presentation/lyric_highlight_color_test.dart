import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/audio_handler.dart';
import 'package:koyze/features/lyric/domain/lyric.dart';
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

/// 固定在某个播放位置的 notifier，用来驱动逐字高亮的进度。
class _FixedPositionNotifier extends PositionNotifier {
  _FixedPositionNotifier(Duration initial) : super(null) {
    update(initial);
  }
}

/// 歌词配色是纯视觉契约，但它是用户最直接能感知的状态指示：
/// 当前行必须是主题强调色，未唱的字不能也被染成强调色（否则整行看不出进度）。
///
/// 这里渲染真实的 `LyricView` 并读取 `Text` 的实际样式，而不是去源码里
/// 找 `activeColor: accent` 这行字。
void main() {
  final accent = const Color(0xFF1DB954);

  setUp(() {
    // seekProvider 的默认实现会读全局 audioHandler；给一个空实现即可，
    // 这些测试只关心颜色，不关心跳转。
    audioHandler = BaseAudioHandler();
  });

  Widget harness({
    required Lyrics lyrics,
    required int currentLine,
    bool fullScreen = true,
    Brightness brightness = Brightness.dark,
  }) {
    return ProviderScope(
      overrides: [
        // LyricView 从 currentLyricLoadProvider 派生歌词，从 seekProvider
        // 取跳转回调。两者都要给出，否则会走到未初始化的 audioHandler。
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
        // 逐字行从 playerPositionProvider 取进度推算已唱到第几个字。
        // 给一个落在第二句中段的位置，让至少一个字已唱完。
        playerPositionProvider.overrideWith(
          () => _FixedPositionNotifier(const Duration(seconds: 7)),
        ),
        currentLineIndexProvider.overrideWithValue(currentLine),
      ],
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: brightness,
          colorScheme: ColorScheme.fromSeed(
            seedColor: accent,
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: LyricView(isFullScreen: fullScreen),
          ),
        ),
      ),
    );
  }

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

  Lyrics plain() => const Lyrics(
        raw: '',
        lines: [
          LyricLine(time: Duration.zero, text: '第一句'),
          LyricLine(time: Duration(seconds: 5), text: '第二句'),
        ],
      );

  /// 歌词文字的颜色不在 `Text.style` 上，而在包裹它的
  /// `AnimatedDefaultTextStyle` / `DefaultTextStyle` 上，
  /// 所以要沿祖先链找最近的一个 DefaultTextStyle。
  Color? effectiveColorOf(WidgetTester tester, String text) {
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) return null;
    final element = finder.evaluate().first;
    DefaultTextStyle? style;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is AnimatedDefaultTextStyle) {
        style = DefaultTextStyle(
          style: widget.style,
          textAlign: widget.textAlign ?? TextAlign.start,
          softWrap: widget.softWrap,
          overflow: widget.overflow,
          maxLines: widget.maxLines,
          child: const SizedBox(),
        );
        return false;
      }
      if (widget is DefaultTextStyle) {
        style = widget;
        return false;
      }
      return true;
    });
    return style?.style.color;
  }

  testWidgets('当前行使用主题强调色', (tester) async {
    await tester.pumpWidget(
      harness(lyrics: plain(), currentLine: 1),
    );
    await tester.pump();

    final theme = Theme.of(
      tester.element(find.byType(LyricView)),
    );
    expect(
      effectiveColorOf(tester, '第二句'),
      theme.colorScheme.primary,
      reason: '当前行文字必须是主题 primary（强调色）',
    );
  });

  testWidgets('非当前行不是强调色', (tester) async {
    await tester.pumpWidget(
      harness(lyrics: plain(), currentLine: 1),
    );
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(LyricView)));
    final other = effectiveColorOf(tester, '第一句');
    expect(other, isNotNull);
    expect(
      other,
      isNot(theme.colorScheme.primary),
      reason: '非当前行不该和当前行同色，否则看不出当前位置',
    );
  });

  testWidgets('逐字歌词用强调色高亮已唱的字', (tester) async {
    await tester.pumpWidget(
      harness(lyrics: withWordTiming(), currentLine: 1),
    );
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(LyricView)));
    // 逐字行会把每个字拆成独立的 Text。已唱的字应带强调色。
    final wordTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => const ['第', '二', '句'].contains(t.data))
        .toList();
    expect(wordTexts, isNotEmpty, reason: '逐字行应渲染出单个字的 Text');

    final hasAccent = wordTexts.any(
      (t) => t.style?.color == theme.colorScheme.primary,
    );
    expect(
      hasAccent,
      isTrue,
      reason: '逐字歌词必须至少有一个字用强调色，否则 KTV 效果失效',
    );
  });

  testWidgets('浅色主题下逐字高亮不退化为黑色', (tester) async {
    await tester.pumpWidget(
      harness(
        lyrics: withWordTiming(),
        currentLine: 1,
        brightness: Brightness.light,
      ),
    );
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(LyricView)));
    final wordTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => const ['第', '二', '句'].contains(t.data))
        .toList();
    expect(wordTexts, isNotEmpty);

    expect(
      wordTexts.any((t) => t.style?.color == theme.colorScheme.primary),
      isTrue,
      reason: '浅色主题下强调色仍应是主题 primary，而不是纯黑',
    );
    expect(
      wordTexts.any((t) => t.style?.color == Colors.black),
      isFalse,
      reason: '不应出现硬编码的黑色，那会盖掉主题色',
    );
  });

  testWidgets('歌词为空时不抛异常', (tester) async {
    await tester.pumpWidget(
      harness(lyrics: Lyrics.empty(), currentLine: -1),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
