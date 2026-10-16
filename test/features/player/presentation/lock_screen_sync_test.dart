import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/presentation/lock_screen_sync.dart';

void main() {
  test('lock screen playback snapshot ignores position-only changes', () {
    final first = PlaybackState(
      playing: true,
      processingState: AudioProcessingState.ready,
      queueIndex: 3,
      updatePosition: const Duration(seconds: 1),
    );
    final second = PlaybackState(
      playing: true,
      processingState: AudioProcessingState.ready,
      queueIndex: 3,
      updatePosition: const Duration(seconds: 2),
    );
    final paused = PlaybackState(
      playing: false,
      processingState: AudioProcessingState.ready,
      queueIndex: 3,
      updatePosition: const Duration(seconds: 2),
    );

    expect(
      lockScreenPlaybackSnapshot(first),
      lockScreenPlaybackSnapshot(second),
    );
    expect(
      lockScreenPlaybackSnapshot(second),
      isNot(lockScreenPlaybackSnapshot(paused)),
    );
  });

  test('sync requests received during a write are drained in order', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final generations = <int>[];
    late final SerializedSyncCoordinator coordinator;
    coordinator = SerializedSyncCoordinator((generation) async {
      generations.add(generation);
      if (generations.length == 1) {
        firstStarted.complete();
        await releaseFirst.future;
        expect(coordinator.owns(generation), isFalse);
      }
    });
    addTearDown(coordinator.dispose);

    final first = coordinator.request();
    await firstStarted.future;
    final second = coordinator.request();
    releaseFirst.complete();
    await Future.wait([first, second]);

    expect(generations, [1, 2]);
    expect(coordinator.owns(2), isTrue);
  });

  test('disposing invalidates and drains an active sync', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    late final SerializedSyncCoordinator coordinator;
    coordinator = SerializedSyncCoordinator((generation) async {
      started.complete();
      await release.future;
      expect(coordinator.owns(generation), isFalse);
    });

    unawaited(coordinator.request());
    await started.future;
    final disposal = coordinator.dispose();
    release.complete();
    await disposal;

    await coordinator.request();
  });
}
