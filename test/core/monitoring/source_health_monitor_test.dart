// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/monitoring/source_health_monitor.dart';

void main() {
  group('SourceHealthMonitor', () {
    late SourceHealthMonitor monitor;

    setUp(() {
      monitor = SourceHealthMonitor();
    });

    tearDown(() {
      monitor.dispose();
    });

    test('should initialize with empty health status', () {
      final status = monitor.getHealthStatus();
      expect(status, isEmpty);
    });

    test('should track health after check', () async {
      await monitor.checkSource(MusicPlatform.qq);
      
      final health = monitor.getHealth(MusicPlatform.qq);
      expect(health, isNotNull);
      expect(health!.lastCheck, isNotNull);
    });

    test('should calculate uptime percentage', () async {
      // Perform multiple checks
      for (int i = 0; i < 5; i++) {
        await monitor.checkSource(MusicPlatform.qq);
      }

      final uptime = monitor.getUptimePercentage(MusicPlatform.qq);
      expect(uptime, greaterThanOrEqualTo(0.0));
      expect(uptime, lessThanOrEqualTo(100.0));
    });

    test('should track health history', () async {
      await monitor.checkSource(MusicPlatform.qq);
      await monitor.checkSource(MusicPlatform.qq);

      final history = monitor.getHistory(MusicPlatform.qq);
      expect(history.length, greaterThanOrEqualTo(2));
    });

    test('should limit history to max entries', () async {
      // Exceed max history
      for (int i = 0; i < 150; i++) {
        await monitor.checkSource(MusicPlatform.qq);
      }

      final history = monitor.getHistory(MusicPlatform.qq);
      expect(history.length, lessThanOrEqualTo(100));
    });

    test('should export health report', () async {
      await monitor.checkSource(MusicPlatform.qq);

      final report = monitor.exportHealthReport();
      expect(report['timestamp'], isNotNull);
      expect(report['overallHealth'], isNotNull);
      expect(report['platforms'], isA<Map>());
    });

    test('should determine overall health status', () async {
      await monitor.checkAllSources();

      final overallHealth = monitor.getOverallHealth();
      expect(overallHealth, isIn(HealthStatus.values));
    });

    test('should emit health updates via stream', () async {
      expectLater(
        monitor.healthStream,
        emitsInOrder([
          isA<Map<MusicPlatform, SourceHealth>>(),
        ]),
      );

      await monitor.checkAllSources();
    });
  });

  group('SourceHealth', () {
    test('should correctly identify healthy status', () {
      final health = SourceHealth(
        status: HealthStatus.healthy,
        lastCheck: DateTime.now(),
        latencyMs: 100,
      );

      expect(health.isHealthy, true);
      expect(health.isDegraded, false);
      expect(health.isDown, false);
    });

    test('should correctly identify degraded status', () {
      final health = SourceHealth(
        status: HealthStatus.degraded,
        lastCheck: DateTime.now(),
        latencyMs: 2000,
      );

      expect(health.isHealthy, false);
      expect(health.isDegraded, true);
      expect(health.isDown, false);
    });

    test('should correctly identify down status', () {
      final health = SourceHealth(
        status: HealthStatus.down,
        lastCheck: DateTime.now(),
        error: 'Connection failed',
      );

      expect(health.isHealthy, false);
      expect(health.isDegraded, false);
      expect(health.isDown, true);
    });
  });

  group('MusicPlatform', () {
    test('should have valid display names', () {
      for (final platform in MusicPlatform.values) {
        expect(platform.displayName, isNotEmpty);
      }
    });

    test('should have valid base URLs', () {
      for (final platform in MusicPlatform.values) {
        expect(platform.baseUrl, startsWith('https://'));
      }
    });
  });
}
