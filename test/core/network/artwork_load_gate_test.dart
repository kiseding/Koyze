import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/network/artwork_load_gate.dart';

void main() {
  test('同时执行数不超过上限，完成后按先来后到补位', () async {
    final gate = ArtworkLoadGate(maxConcurrent: 2);
    final started = <int>[];
    final gates = List.generate(5, (_) => Completer<void>());

    final futures = List.generate(
      5,
      (i) => gate.run(() async {
        started.add(i);
        await gates[i].future;
      }),
    );

    await pumpEventQueue();
    expect(started, [0, 1], reason: '前两个先跑，其余排队');
    expect(gate.activeCount, 2);
    expect(gate.waitingCount, 3);

    gates[0].complete();
    await pumpEventQueue();
    expect(started, [0, 1, 2], reason: '空出一个名额，队首补上');

    gates[1].complete();
    gates[2].complete();
    await pumpEventQueue();
    expect(started, [0, 1, 2, 3, 4]);

    for (final completer in gates) {
      if (!completer.isCompleted) completer.complete();
    }
    await Future.wait(futures);
    expect(gate.activeCount, 0);
    expect(gate.waitingCount, 0);
  });

  test('任务抛错也把名额还回去', () async {
    final gate = ArtworkLoadGate(maxConcurrent: 1);
    final failing = gate.run<void>(() async => throw StateError('boom'));
    await expectLater(failing, throwsStateError);

    var ran = false;
    await gate.run(() async {
      ran = true;
    });
    expect(ran, isTrue, reason: '上一个任务失败不能把名额永久占住');
    expect(gate.activeCount, 0);
  });

  test('上限为 1 时严格串行', () async {
    final gate = ArtworkLoadGate(maxConcurrent: 1);
    var running = 0;
    var peak = 0;
    await Future.wait([
      for (var i = 0; i < 4; i++)
        gate.run(() async {
          running += 1;
          if (running > peak) peak = running;
          await Future<void>.delayed(Duration.zero);
          running -= 1;
        }),
    ]);
    expect(peak, 1);
    expect(gate.activeCount, 0);
  });
}
