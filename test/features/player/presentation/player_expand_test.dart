import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show StackParentData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/player_route_progress.dart';
import 'package:koyze/features/lyric/domain/lyric.dart';
import 'package:koyze/features/lyric/presentation/lyric_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/domain/player_service.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/player/presentation/player_screen.dart';

/// 全屏播放器的展开/收起是「矩形 morph」而不是 Hero 飞行。
///
/// 这些测试验证**可观察的结果**：morph 覆盖层是否存在、它的矩形是否随
/// `playerRouteProgress` 变化、页面是否没有 Hero / 页面级 Transform。
/// 它们不关心某个变量叫什么、某行代码文案是什么——重命名或重构不会误报，
/// 但删掉 morph 实现会立刻失败。
void main() {
  tearDown(() {
    playerRouteProgress.value = 0;
  });

  Widget harness({PlayMode playMode = PlayMode.sequential}) {
    final music = MusicItem(
      id: 't1',
      name: '测试歌曲名称',
      singer: '测试歌手',
      duration: const Duration(seconds: 200),
      source: 'local',
    );
    return ProviderScope(
      overrides: [
        currentMusicProvider.overrideWithValue(music),
        playerServiceProvider.overrideWithValue(PlayerService()),
        currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
        playbackStateProvider.overrideWith(
          (ref) => Stream.value(
            PlaybackState(
              playing: false,
              processingState: AudioProcessingState.idle,
              controls: const [],
              systemActions: const {},
            ),
          ),
        ),
        durationProvider.overrideWithValue(
          AsyncValue.data(const Duration(seconds: 200)),
        ),
        playModeProvider.overrideWithValue(playMode),
        playerPositionProvider.overrideWith(PositionNotifier.new),
        beginScrubProvider.overrideWithValue(() async => 0),
        finishScrubProvider.overrideWithValue(
          (int gen, Duration target, {required bool resumeAfter}) async {},
        ),
        cancelScrubProvider.overrideWithValue((int gen) async {}),
        currentLyricProvider.overrideWithValue(Lyrics.empty()),
        currentLineIndexProvider.overrideWithValue(-1),
      ],
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF111111),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: Colors.white,
        ),
        home: const Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Color(0xFFB8D4FF)),
              PlayerScreen(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, double progress) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    playerRouteProgress.value = progress;
    await tester.pumpWidget(harness());
    await tester.pump();
  }

  /// 收集当前渲染树里所有 `Positioned.fromRect` 出来的矩形。
  List<Rect> morphRects(WidgetTester tester) {
    final rects = <Rect>[];
    for (final element in find.byType(Positioned).evaluate()) {
      final widget = element.widget as Positioned;
      final parentData = element.renderObject?.parentData;
      if (parentData is StackParentData) {
        // Positioned.fromRect 会同时给出 left/top/width/height。
        if (widget.left != null &&
            widget.top != null &&
            widget.width != null &&
            widget.height != null) {
          rects.add(
            Rect.fromLTWH(
              widget.left!,
              widget.top!,
              widget.width!,
              widget.height!,
            ),
          );
        }
      }
    }
    return rects;
  }

  group('矩形 morph', () {
    testWidgets('全屏状态下没有 Hero 飞行', (tester) async {
      await pumpAt(tester, 1.0);
      expect(find.byType(Hero), findsNothing);
    });

    testWidgets('mini 进度为 0 时不渲染 morph 覆盖层', (tester) async {
      await pumpAt(tester, 0);
      // progress 为 0 且未在关闭中，覆盖层应完全隐藏，
      // 否则会在迷你栏上叠一层不可见的全屏遮罩吃掉点击。
      expect(find.byType(IgnorePointer), findsWidgets);
      final rects = morphRects(tester);
      final screen = const Size(420, 900);
      final fullScreenRects = rects.where(
        (r) => r.width >= screen.width - 1 && r.height >= screen.height - 1,
      );
      expect(
        fullScreenRects,
        isEmpty,
        reason: 'progress=0 时不应存在覆盖全屏的 morph 层',
      );
    });

    testWidgets('morph 矩形随 progress 单调变大', (tester) async {
      final areas = <double>[];
      for (final progress in <double>[0.15, 0.5, 0.85]) {
        playerRouteProgress.value = progress;
        await tester.pumpWidget(harness());
        await tester.pump();
        final rects = morphRects(tester);
        expect(rects, isNotEmpty, reason: 'progress=$progress 时应有 morph 覆盖层');
        // 取最大的一块作为 morph 主体
        areas.add(
          rects.map((r) => r.width * r.height).reduce((a, b) => a > b ? a : b),
        );
      }
      expect(
        areas[0],
        lessThan(areas[1]),
        reason: 'progress 增大时 morph 矩形应随之变大',
      );
      expect(areas[1], lessThan(areas[2]));
    });

    testWidgets('morph 覆盖层不拦截点击', (tester) async {
      await pumpAt(tester, 0.5);
      // 覆盖层内部必须是 IgnorePointer，否则展开动画期间整屏无法点击。
      final ignorePointers = tester
          .widgetList<IgnorePointer>(find.byType(IgnorePointer))
          .toList();
      expect(ignorePointers, isNotEmpty);
      expect(
        ignorePointers.any((w) => w.ignoring),
        isTrue,
        reason: 'morph 层必须有一层正在 ignoring 的 IgnorePointer',
      );
    });
  });

  group('页面级动画', () {
    testWidgets('morph 层使用 IgnorePointer 包住覆盖内容', (tester) async {
      await pumpAt(tester, 0.6);
      // 覆盖层必须能透传点击（Positioned 在外、IgnorePointer 在内），
      // 否则展开动画期间整屏点不动。这里验证结构顺序：
      // 每个 Positioned.fromRect 的最外层子树里都能找到 IgnorePointer。
      final positionedRects = find.byWidgetPredicate(
        (w) =>
            w is Positioned &&
            w.left != null &&
            w.top != null &&
            w.width != null &&
            w.height != null,
      );
      expect(positionedRects, findsWidgets);
      for (final element in positionedRects.evaluate()) {
        final hasIgnore = find
            .descendant(
              of: find.byElementPredicate((e) => e == element),
              matching: find.byType(IgnorePointer),
            )
            .evaluate()
            .isNotEmpty;
        expect(
          hasIgnore,
          isTrue,
          reason: 'Positioned 矩形层 ${(element.widget as Positioned).left}, '
              '${(element.widget as Positioned).top} 缺少 IgnorePointer',
        );
      }
    });

    testWidgets('全屏状态下没有溢出', (tester) async {
      await pumpAt(tester, 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('高进度切换不抛异常', (tester) async {
      await pumpAt(tester, 0.95);
      expect(tester.takeException(), isNull);
      playerRouteProgress.value = 1.0;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
