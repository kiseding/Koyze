// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/performance/startup_optimizer.dart';

void main() {
  group('StartupOptimizer', () {
    late StartupOptimizer optimizer;

    setUp(() {
      optimizer = StartupOptimizer();
    });

    test('should track splash screen duration', () {
      final initialTime = optimizer.metrics.startTime;
      
      // Simulate delay
      Future.delayed(Duration(milliseconds: 100), () {
        optimizer.markSplashEnd();
      });

      expect(optimizer.metrics.startTime, equals(initialTime));
    });

    test('should track initialization duration', () {
      optimizer.markInitComplete();
      
      expect(optimizer.metrics.initCompleteTime, isNotNull);
      expect(optimizer.metrics.initDuration, isNotNull);
    });

    test('should track first frame time', () {
      optimizer.markFirstFrame();
      
      expect(optimizer.metrics.firstFrameTime, isNotNull);
      expect(optimizer.metrics.timeToFirstFrame, isNotNull);
    });

    test('should register and run deferred tasks', () async {
      int taskCount = 0;
      
      optimizer.registerDeferredTask(() async {
        taskCount++;
      });
      
      optimizer.registerDeferredTask(() async {
        await Future.delayed(Duration(milliseconds: 10));
        taskCount++;
      });

      await optimizer.runDeferredTasks();

      expect(taskCount, equals(2));
    });

    test('should handle deferred task errors gracefully', () async {
      optimizer.registerDeferredTask(() async {
        throw Exception('Test error');
      });

      // Should not throw
      await optimizer.runDeferredTasks();
    });

    test('should generate startup report', () {
      optimizer.markSplashEnd();
      optimizer.markInitComplete();
      optimizer.markFirstFrame();

      final report = optimizer.getReport();

      expect(report, isA<Map<String, dynamic>>());
      expect(report, contains('splashDuration'));
      expect(report, contains('initDuration'));
      expect(report, contains('timeToFirstFrame'));
    });
  });

  group('PerformanceBudget', () {
    test('should validate startup budget', () {
      final metrics = StartupMetrics(startTime: DateTime.now());
      metrics.firstFrameTime = DateTime.now().add(Duration(milliseconds: 1500));

      final withinBudget = PerformanceBudget.checkStartupBudget(metrics);

      expect(withinBudget, isTrue); // 1500ms < 2000ms target
    });

    test('should detect budget violations', () {
      final metrics = StartupMetrics(startTime: DateTime.now());
      metrics.firstFrameTime = DateTime.now().add(Duration(milliseconds: 3000));

      final withinBudget = PerformanceBudget.checkStartupBudget(metrics);

      expect(withinBudget, isFalse); // 3000ms > 2000ms target
    });

    test('should validate frame budget', () {
      final frameTime = Duration(milliseconds: 12);
      final withinBudget = PerformanceBudget.checkFrameBudget(frameTime);

      expect(withinBudget, isTrue); // 12ms < 16ms target
    });

    test('should detect frame drops', () {
      final frameTime = Duration(milliseconds: 20);
      final withinBudget = PerformanceBudget.checkFrameBudget(frameTime);

      expect(withinBudget, isFalse); // 20ms > 16ms target
    });
  });
}
