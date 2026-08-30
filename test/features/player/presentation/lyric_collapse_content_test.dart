import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/card_expand.dart';
import 'package:koyze/core/player_route_progress.dart';
import 'package:koyze/features/lyric/domain/lyric.dart';
import 'package:koyze/features/lyric/presentation/lyric_provider.dart';
import 'package:koyze/features/lyric/presentation/lyric_view.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/domain/player_service.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/player/presentation/player_screen.dart';

void main() {
  tearDown(() {
    playerRouteProgress.value = 0;
    playerRouteDismissLocked = false;
    edgeDragActive = false;
  });

  Widget harness() {
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
        playModeProvider.overrideWithValue(PlayMode.sequential),
        playerPositionProvider.overrideWith((ref) => PositionNotifier(null)),
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
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFFB8D4FF)),
              const PlayerScreen(),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('lyric page collapse keeps rendering lyric content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    playerRouteProgress.value = 1.0;
    await tester.pumpWidget(harness());
    await tester.pump();

    // 切到歌词页（PageView 横滑）。
    await tester.drag(
      find.byType(PageView),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('歌词'), findsOneWidget);
    expect(find.text('正在播放'), findsNothing);

    // 模拟左缘右滑：progress 降到 0.5（lyricCollapsing 生效区间）。
    playerRouteProgress.value = 0.5;
    edgeDragActive = true;
    await tester.pump();
    await tester.pump();

    // 动效期间必须仍是歌词页内容：标题"歌词"、LyricView 在场；
    // 封面页标题"正在播放"绝不能出现（出现即代表切回了全屏播放器）。
    // 守卫根因：两个结构不同的渲染分支会在 lyricCollapsing 翻转时
    // 销毁重建整棵子树，PageView 重新 attach 回退到第 0 页（封面页）。
    expect(find.text('歌词'), findsOneWidget);
    expect(find.byType(LyricView), findsOneWidget);
    expect(find.text('正在播放'), findsNothing);

    edgeDragActive = false;
  });
}
