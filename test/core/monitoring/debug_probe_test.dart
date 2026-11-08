// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/monitoring/debug_probe.dart';
import 'package:koyze/core/monitoring/performance_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(DebugProbe.resetForTesting);
  tearDown(DebugProbe.resetForTesting);

  test('默认取值由编译期开关与环境变量共同决定', () {
    expect(DebugProbe.enabled, DebugProbe.staticallyEnabled);
    expect(
      DebugProbe.describe(),
      anyOf('off', 'compile-time', 'environment'),
      reason: '没有强制覆盖时，来源只能是默认值',
    );
  });

  test('运行期强制开关优先于默认值', () {
    DebugProbe.forced = true;
    expect(DebugProbe.enabled, isTrue);
    expect(DebugProbe.describe(), 'forced');

    DebugProbe.forced = false;
    expect(DebugProbe.enabled, isFalse);

    // 传回 null 表示交还默认值，而不是「关掉」。
    DebugProbe.forced = null;
    expect(DebugProbe.enabled, DebugProbe.staticallyEnabled);
  });

  test('未打开探针时 PerformanceMonitor 不接帧回调', () {
    DebugProbe.forced = false;
    final monitor = PerformanceMonitor();
    monitor.initialize();
    addTearDown(monitor.dispose);

    expect(monitor.frameProbeRunning, isFalse);

    monitor.startFrameProbe();
    expect(monitor.frameProbeRunning, isTrue, reason: '手动打开应立即接线');

    monitor.stopFrameProbe();
    expect(monitor.frameProbeRunning, isFalse);
  });

  testWidgets('诊断面板关掉后探针不残留定时器', (tester) async {
    DebugProbe.forced = false;
    final monitor = PerformanceMonitor();
    monitor.initialize();
    monitor.startFrameProbe();

    await tester.pump(const Duration(milliseconds: 16));
    expect(monitor.frameProbeRunning, isTrue);

    monitor.stopFrameProbe();
    monitor.dispose();
    expect(monitor.frameProbeRunning, isFalse);
  });
}
