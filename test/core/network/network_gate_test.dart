// 「一次批量里最多几条同时在飞」。
//
// 这条闸门是为启动期网络风暴加的：推荐候选是「查询词 × 平台」的笛卡尔积，
// 20~25 条一起发出去，弱网下会集体 connectionTimeout，十秒后又同一毫秒
// 一起失败返回，把同等数量的异常砸在同一帧的 UI isolate 上。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/network/network_gate.dart';

void main() {
  test('同时在跑的任务不超过上限', () async {
    final gate = NetworkGate(maxConcurrent: 3);
    var running = 0;
    var peak = 0;

    final tasks = [
      for (var i = 0; i < 12; i++)
        gate.run(() async {
          running++;
          if (running > peak) peak = running;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
        }),
    ];
    await Future.wait(tasks);

    expect(peak, 3, reason: '峰值并发必须正好卡在上限');
    expect(gate.activeCount, 0);
    expect(gate.waitingCount, 0);
  });

  test('默认上限是 3', () {
    expect(NetworkGate().maxConcurrent, 3);
  });

  test('任务抛异常也要把名额还回去', () async {
    final gate = NetworkGate(maxConcurrent: 1);

    await expectLater(
      gate.run<void>(() async => throw StateError('boom')),
      throwsStateError,
    );

    // 名额没漏：第二个任务还能正常进来。
    final value = await gate.run(() async => 42);
    expect(value, 42);
    expect(gate.activeCount, 0);
  });

  test('排队按提交顺序放行', () async {
    final gate = NetworkGate(maxConcurrent: 1);
    final order = <int>[];
    final hold = Completer<void>();

    final first = gate.run(() async {
      await hold.future;
      order.add(1);
    });
    final second = gate.run(() async => order.add(2));
    final third = gate.run(() async => order.add(3));

    hold.complete();
    await Future.wait([first, second, third]);

    expect(order, [1, 2, 3]);
  });
}
