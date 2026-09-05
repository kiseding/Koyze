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

void main() {
  tearDown(() {
    playerRouteProgress.value = 0;
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
          const AsyncValue.data(Duration(seconds: 200)),
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

  testWidgets(
    'pull down follows finger and settles back when under threshold',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      playerRouteProgress.value = 1.0;
      await tester.pumpWidget(harness());
      await tester.pump();

      // 拖动中（未松手）：progress 应跟手下降（200px / 378px 满程）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PlayerScreen)),
      );
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await gesture.moveBy(const Offset(0, 175));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final duringDrag = playerRouteProgress.value;
      debugPrint('during drag progress=$duringDrag');
      expect(duringDrag, lessThan(0.9));
      expect(duringDrag, greaterThan(0.2));

      // 松手（低于阈值 screenH*0.4=360）→ 回弹到 1
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(playerRouteProgress.value, 1.0);
    },
  );

  testWidgets('release after segmented drag plays the settle animation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    playerRouteProgress.value = 1.0;
    await tester.pumpWidget(harness());
    await tester.pump();

    // 连续多段移动（模拟真实手指轨迹），未过阈值松手 → 必须播放回弹动画
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PlayerScreen)),
    );
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await tester.pump();
    final before = playerRouteProgress.value;
    debugPrint('before release progress=$before');
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final mid = playerRouteProgress.value;
    debugPrint('after release 16ms progress=$mid');
    // 回弹动画必须正在向 1 播放（progress 比松手时更大）。
    expect(mid, greaterThan(before));
    await tester.pump(const Duration(milliseconds: 400));
    expect(playerRouteProgress.value, closeTo(1.0, 0.01));
  });

  testWidgets('partial drag cancelled by another gesture settles back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    playerRouteProgress.value = 1.0;
    await tester.pumpWidget(harness());
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PlayerScreen)),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await tester.pump();
    expect(playerRouteProgress.value, greaterThan(0.5));
    // 手势被抢占（PointerCancel）→ 必须自动回弹全屏，绝不卡半路。
    await gesture.cancel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(playerRouteProgress.value, closeTo(1.0, 0.01));
  });

  testWidgets(
    'pull past threshold continues collapse from current position then pops',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      playerRouteProgress.value = 1.0;
      await tester.pumpWidget(harness());
      await tester.pump();
      expect(playerRouteDismissLocked, isFalse);

      await tester.drag(find.byType(PlayerScreen), const Offset(0, 425));
      await tester.pump();
      await tester.pump();
      // 超过满程 → 已跟手收拢到 0
      expect(playerRouteProgress.value, 0.0);

      // 松手后继续收拢（不会先弹回），动画完成 pop + 加锁。
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(playerRouteProgress.value, 0.0);
      expect(playerRouteDismissLocked, isTrue);
    },
  );
}
