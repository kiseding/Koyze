import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';

void main() {
  testWidgets('timer publishes idle only after pause succeeds', (tester) async {
    final pause = Completer<void>();
    var pauseCalls = 0;
    final notifier = SleepTimerNotifier(() {
      pauseCalls++;
      return pause.future;
    });
    addTearDown(notifier.dispose);

    notifier.startTimer(const Duration(seconds: 1));
    expect(notifier.value, isA<SleepTimerRunning>());
    await tester.pump(const Duration(seconds: 1));

    expect(pauseCalls, 1);
    expect(notifier.value, isA<SleepTimerRunning>());

    pause.complete();
    await tester.pump();
    expect(notifier.value, isA<SleepTimerIdle>());
  });

  testWidgets('timer exposes pause failure deterministically', (tester) async {
    const duration = Duration(seconds: 1);
    final failure = StateError(
      'pause failed token=secret-token https://user:password@example.com',
    );
    final notifier = SleepTimerNotifier(() async => throw failure);
    addTearDown(notifier.dispose);

    notifier.startTimer(duration);
    await tester.pump(duration);
    await tester.pump();

    final state = notifier.value;
    expect(state, isA<SleepTimerFailed>());
    expect(
      (state as SleepTimerFailed).reason,
      SleepTimerFailureReason.pauseFailed,
    );
    expect(state.duration, duration);
    expect(state.endTime, isNull);
    expect(state.toString(), isNot(contains('secret-token')));
    expect(state.toString(), isNot(contains('example.com')));
  });

  testWidgets('failed timer can retry and cancel explicitly', (tester) async {
    var pauseCalls = 0;
    final notifier = SleepTimerNotifier(() async {
      pauseCalls++;
      if (pauseCalls == 1) throw StateError('pause failed');
    });
    addTearDown(notifier.dispose);

    notifier.startTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(notifier.value, isA<SleepTimerFailed>());

    notifier.retryTimer();
    expect(notifier.value, isA<SleepTimerRunning>());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(pauseCalls, 2);
    expect(notifier.value, isA<SleepTimerIdle>());

    notifier.startTimer(const Duration(seconds: 1));
    notifier.cancelTimer();
    expect(notifier.value, isA<SleepTimerIdle>());
  });

  testWidgets('reset prevents an old pause completion from publishing', (
    tester,
  ) async {
    final oldPause = Completer<void>();
    var pauseCalls = 0;
    final notifier = SleepTimerNotifier(() {
      pauseCalls++;
      return oldPause.future;
    });
    addTearDown(notifier.dispose);

    notifier.startTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    notifier.startTimer(const Duration(minutes: 1));
    final replacement = notifier.value as SleepTimerRunning;

    oldPause.complete();
    await tester.pump();
    expect(notifier.value, same(replacement));
    expect(pauseCalls, 1);
    notifier.cancelTimer();
  });

  testWidgets('cancel prevents an old pause failure from publishing', (
    tester,
  ) async {
    final oldPause = Completer<void>();
    final notifier = SleepTimerNotifier(() => oldPause.future);
    addTearDown(notifier.dispose);

    notifier.startTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    notifier.cancelTimer();

    oldPause.completeError(StateError('late failure'));
    await tester.pump();
    expect(notifier.value, isA<SleepTimerIdle>());
  });

  testWidgets('dispose prevents an old pause failure from escaping the zone', (
    tester,
  ) async {
    final oldPause = Completer<void>();
    final notifier = SleepTimerNotifier(() => oldPause.future);

    notifier.startTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    notifier.dispose();

    oldPause.completeError(StateError('late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('untilTrackEnd publishes a distinct state with no deadline', (
    tester,
  ) async {
    var pauseCalls = 0;
    final notifier = SleepTimerNotifier(() async => pauseCalls++);
    addTearDown(notifier.dispose);

    notifier.startUntilTrackEnd();

    final state = notifier.value;
    expect(state, isA<SleepTimerUntilTrackEnd>());
    expect((state as SleepTimerUntilTrackEnd).fadeOut, isTrue);
    expect(state.endTime, isNull);
    // 「播完就停」不该有墙钟定时器，否则歌比预期长就会提前掐断。
    await tester.pump(const Duration(minutes: 5));
    expect(pauseCalls, 0);
    expect(notifier.value, isA<SleepTimerUntilTrackEnd>());
  });

  testWidgets('untilTrackEnd honours fadeOut: false', (tester) async {
    final notifier = SleepTimerNotifier(() async {});
    addTearDown(notifier.dispose);

    notifier.startUntilTrackEnd(fadeOut: false);

    expect((notifier.value as SleepTimerUntilTrackEnd).fadeOut, isFalse);
  });

  testWidgets('untilTrackEnd can be cancelled', (tester) async {
    final notifier = SleepTimerNotifier(() async {});
    addTearDown(notifier.dispose);

    notifier.startUntilTrackEnd();
    notifier.cancelTimer();

    expect(notifier.value, isA<SleepTimerIdle>());
  });

  testWidgets('starting a countdown replaces untilTrackEnd', (tester) async {
    final notifier = SleepTimerNotifier(() async {});
    addTearDown(notifier.dispose);

    notifier.startUntilTrackEnd();
    notifier.startTimer(const Duration(minutes: 2), fadeOut: false);

    final running = notifier.value as SleepTimerRunning;
    expect(running.fadeOut, isFalse);
    expect(running.duration, const Duration(minutes: 2));
    notifier.cancelTimer();
  });

  testWidgets('fadeOut is recorded on the running state', (tester) async {
    final notifier = SleepTimerNotifier(() async {});
    addTearDown(notifier.dispose);

    notifier.startTimer(const Duration(minutes: 2));
    expect((notifier.value as SleepTimerRunning).fadeOut, isTrue);

    notifier.startTimer(const Duration(minutes: 2), fadeOut: false);
    expect((notifier.value as SleepTimerRunning).fadeOut, isFalse);
    notifier.cancelTimer();
  });

  testWidgets('retry keeps the fadeOut preference', (tester) async {
    var pauseCalls = 0;
    final notifier = SleepTimerNotifier(() async {
      pauseCalls++;
      if (pauseCalls == 1) throw StateError('pause failed');
    });
    addTearDown(notifier.dispose);

    notifier.startTimer(const Duration(seconds: 1), fadeOut: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(notifier.value, isA<SleepTimerFailed>());

    notifier.retryTimer();
    expect((notifier.value as SleepTimerRunning).fadeOut, isFalse);
    notifier.cancelTimer();
  });
}
