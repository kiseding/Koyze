// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/monitoring/performance_monitor.dart';

void main() {
  group('PerformanceMonitor', () {
    late PerformanceMonitor monitor;

    setUp(() {
      monitor = PerformanceMonitor();
      monitor.initialize();
    });

    tearDown(() {
      monitor.clearMetrics();
      monitor.dispose();
    });

    test('should record metric', () {
      final metric = PerformanceMetric(
        name: 'test_operation',
        timestamp: DateTime.now(),
        durationMs: 100,
      );

      monitor.recordMetric(metric);

      final metrics = monitor.getMetrics('test_operation');
      expect(metrics.length, 1);
      expect(metrics.first.name, 'test_operation');
      expect(metrics.first.durationMs, 100);
    });

    test('should start and stop trace', () {
      final trace = monitor.startTrace('test_trace');
      
      // Simulate some work
      for (int i = 0; i < 1000; i++) {
        // Busy work
      }

      final metric = trace.stop();
      
      expect(metric.name, 'test_trace');
      expect(metric.durationMs, greaterThan(0));
    });

    test('should measure synchronous operation', () {
      int result = monitor.measure('sync_op', () {
        return 42;
      });

      expect(result, 42);
      
      final metrics = monitor.getMetrics('sync_op');
      expect(metrics.length, 1);
      expect(metrics.first.durationMs, greaterThanOrEqualTo(0));
    });

    test('should measure asynchronous operation', () async {
      int result = await monitor.measureAsync('async_op', () async {
        await Future.delayed(Duration(milliseconds: 10));
        return 42;
      });

      expect(result, 42);
      
      final metrics = monitor.getMetrics('async_op');
      expect(metrics.length, 1);
      expect(metrics.first.durationMs, greaterThan(5));
    });

    test('should include attributes in metrics', () {
      monitor.measure(
        'operation_with_attrs',
        () => 42,
        attributes: {'userId': 'test-123', 'feature': 'player'},
      );

      final metrics = monitor.getMetrics('operation_with_attrs');
      expect(metrics.first.attributes['userId'], 'test-123');
      expect(metrics.first.attributes['feature'], 'player');
    });

    test('should calculate average duration', () {
      for (int i = 0; i < 5; i++) {
        monitor.recordMetric(PerformanceMetric(
          name: 'test_op',
          timestamp: DateTime.now(),
          durationMs: 100 + i * 10,
        ));
      }

      final avg = monitor.getAverageDuration('test_op');
      expect(avg, isNotNull);
      expect(avg!, closeTo(120, 1));
    });

    test('should calculate percentile duration', () {
      final durations = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
      
      for (final duration in durations) {
        monitor.recordMetric(PerformanceMetric(
          name: 'test_op',
          timestamp: DateTime.now(),
          durationMs: duration,
        ));
      }

      final p50 = monitor.getPercentileDuration('test_op', 0.5);
      final p95 = monitor.getPercentileDuration('test_op', 0.95);
      final p99 = monitor.getPercentileDuration('test_op', 0.99);

      expect(p50, closeTo(55, 10));
      expect(p95, greaterThanOrEqualTo(90));
      expect(p99, greaterThanOrEqualTo(95));
    });

    test('should limit metric storage', () {
      // Exceed max metrics
      for (int i = 0; i < 1500; i++) {
        monitor.recordMetric(PerformanceMetric(
          name: 'test_$i',
          timestamp: DateTime.now(),
          durationMs: i,
        ));
      }

      final allMetrics = monitor.getAllMetrics();
      expect(allMetrics.length, lessThanOrEqualTo(1000));
    });

    test('should export performance report', () {
      monitor.recordMetric(PerformanceMetric(
        name: 'test_op',
        timestamp: DateTime.now(),
        durationMs: 100,
      ));

      final report = monitor.exportReport();
      
      expect(report['timestamp'], isNotNull);
      expect(report['metrics'], isA<Map>());
      expect(report['totalMetrics'], greaterThan(0));
    });

    test('should clear all metrics', () {
      monitor.recordMetric(PerformanceMetric(
        name: 'test',
        timestamp: DateTime.now(),
        durationMs: 100,
      ));

      expect(monitor.getAllMetrics().length, 1);
      
      monitor.clearMetrics();
      
      expect(monitor.getAllMetrics().length, 0);
    });
  });

  group('PerformanceTrace', () {
    test('should track elapsed time', () async {
      final trace = PerformanceTrace('test_trace');
      
      await Future.delayed(Duration(milliseconds: 50));
      
      expect(trace.elapsedMs, greaterThanOrEqualTo(40));
    });

    test('should include attributes', () {
      final trace = PerformanceTrace(
        'test_trace',
        attributes: {'key': 'value'},
      );

      final metric = trace.stop();
      expect(metric.attributes['key'], 'value');
    });
  });

  group('PerformanceMetric', () {
    test('should serialize to JSON', () {
      final metric = PerformanceMetric(
        name: 'test_operation',
        timestamp: DateTime(2024, 1, 1),
        durationMs: 150,
        attributes: {'userId': 'test-123'},
      );

      final json = metric.toJson();
      expect(json['name'], 'test_operation');
      expect(json['durationMs'], 150);
      expect(json['attributes']['userId'], 'test-123');
    });
  });

  group('FrameStats', () {
    test('should calculate dropped frame rate', () {
      final stats = FrameStats(
        totalFrames: 100,
        droppedFrames: 5,
        averageFrameTime: 16.5,
        p95FrameTime: 18.0,
        p99FrameTime: 20.0,
        collectedAt: DateTime.now(),
      );

      expect(stats.droppedFrameRate, 5.0);
    });

    test('should handle zero frames', () {
      final stats = FrameStats(
        totalFrames: 0,
        droppedFrames: 0,
        averageFrameTime: 0.0,
        p95FrameTime: 0.0,
        p99FrameTime: 0.0,
        collectedAt: DateTime.now(),
      );

      expect(stats.droppedFrameRate, 0.0);
    });

    test('should serialize to JSON', () {
      final stats = FrameStats(
        totalFrames: 100,
        droppedFrames: 5,
        averageFrameTime: 16.5,
        p95FrameTime: 18.0,
        p99FrameTime: 20.0,
        collectedAt: DateTime(2024, 1, 1),
      );

      final json = stats.toJson();
      expect(json['totalFrames'], 100);
      expect(json['droppedFrames'], 5);
      expect(json['droppedFrameRate'], 5.0);
    });
  });

  group('MemorySnapshot', () {
    test('should convert bytes to MB', () {
      final snapshot = MemorySnapshot(
        rssBytes: 100 * 1024 * 1024, // 100 MB
        heapBytes: 50 * 1024 * 1024,  // 50 MB
        timestamp: DateTime.now(),
      );

      expect(snapshot.rssMB, closeTo(100.0, 0.1));
      expect(snapshot.heapMB, closeTo(50.0, 0.1));
    });

    test('should serialize to JSON', () {
      final snapshot = MemorySnapshot(
        rssBytes: 100 * 1024 * 1024,
        heapBytes: 50 * 1024 * 1024,
        timestamp: DateTime(2024, 1, 1),
      );

      final json = snapshot.toJson();
      expect(json['rssBytes'], 100 * 1024 * 1024);
      expect(json['rssMB'], closeTo(100.0, 0.1));
    });
  });
}
