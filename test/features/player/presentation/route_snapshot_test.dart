import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/player_route_progress.dart';
import 'package:koyze/features/lyric/domain/lyric.dart';
import 'package:koyze/features/lyric/presentation/lyric_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/domain/player_service.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/player/presentation/player_screen.dart';

/// 播放页转场快照：正文只画一次，进度 tick 不再重建整棵子树；
/// 进出场期间缩放的是 RepaintBoundary 抓出来的位图。
void main() {
  tearDown(() {
    playerRouteProgress.value = 0;
    playerRouteDismissLocked = false;
  });

  Widget harness() {
    final music = MusicItem(
      id: 'snapshot-t1',
      name: '快照测试歌曲',
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

  testWidgets('进度 tick 不重建播放器正文', (tester) async {
    await pumpAt(tester, 0.4);
    // 等首帧抓图完成（抓图会切一次 captureMode 并重建正文）。
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    final bodyFinder = find.descendant(
      of: find.byType(PlayerScreen),
      matching: find.byType(Scaffold),
    );
    final before = tester.widgetList<Scaffold>(bodyFinder).single;

    for (final progress in <double>[0.45, 0.5, 0.55, 0.6]) {
      playerRouteProgress.value = progress;
      await tester.pump();
    }

    final after = tester.widgetList<Scaffold>(bodyFinder).single;
    expect(
      identical(before, after),
      isTrue,
      reason: '进度变化只应改外层矩形，正文 Widget 必须复用',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('转场期间用位图替代实时正文', (tester) async {
    await pumpAt(tester, 1.0);
    // 让首帧的 RepaintBoundary 有机会被抓成位图。
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    playerRouteProgress.value = 0.5;
    await tester.pump();
    await tester.pump();

    final snapshots = tester
        .widgetList<RawImage>(
          find.descendant(
            of: find.byType(PlayerScreen),
            matching: find.byType(RawImage),
          ),
        )
        .where((w) => w.image != null)
        .toList();
    expect(snapshots, isNotEmpty, reason: '转场期间应显示抓到的播放页位图');
    expect(snapshots.first.width, 420);
    expect(snapshots.first.height, 900);
    expect(tester.takeException(), isNull);
  });
}
