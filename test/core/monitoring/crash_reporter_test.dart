// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/monitoring/crash_reporter.dart';

void main() {
  group('CrashReporter', () {
    late CrashReporter reporter;

    setUp(() {
      reporter = CrashReporter();
    });

    tearDown(() {
      reporter.clearReports();
    });

    test('should capture exception', () {
      final exception = Exception('Test error');
      
      reporter.captureException(
        exception,
        severity: ErrorSeverity.error,
      );

      final reports = reporter.getReports();
      expect(reports.length, 1);
      expect(reports.first.exception.toString(), contains('Test error'));
      expect(reports.first.severity, ErrorSeverity.error);
    });

    test('should capture exception with stack trace', () {
      try {
        throw Exception('Test error');
      } catch (e, stack) {
        reporter.captureException(e, stackTrace: stack);
      }

      final reports = reporter.getReports();
      expect(reports.first.stackTrace, isNotNull);
    });

    test('should capture message', () {
      reporter.captureMessage(
        'Test message',
        severity: ErrorSeverity.info,
      );

      final reports = reporter.getReports();
      expect(reports.length, 1);
      expect(reports.first.exception, 'Test message');
      expect(reports.first.severity, ErrorSeverity.info);
    });

    test('should set user context', () {
      reporter.setUser('user-123');
      reporter.captureMessage('Test');

      final reports = reporter.getReports();
      expect(reports.first.userId, 'user-123');
    });

    test('should set global context', () {
      reporter.setContext('appVersion', '1.0.0');
      reporter.captureMessage('Test');

      final reports = reporter.getReports();
      expect(reports.first.context['appVersion'], '1.0.0');
    });

    test('should include additional context in report', () {
      reporter.captureException(
        Exception('Test'),
        context: {'feature': 'player', 'action': 'play'},
      );

      final reports = reporter.getReports();
      expect(reports.first.context['feature'], 'player');
      expect(reports.first.context['action'], 'play');
    });

    test('should filter reports by severity', () {
      reporter.captureMessage('Info', severity: ErrorSeverity.info);
      reporter.captureMessage('Warning', severity: ErrorSeverity.warning);
      reporter.captureMessage('Error', severity: ErrorSeverity.error);

      final errorReports = reporter.getReports(minSeverity: ErrorSeverity.error);
      expect(errorReports.length, 1);
      expect(errorReports.first.severity, ErrorSeverity.error);
    });

    test('should limit returned reports', () {
      for (int i = 0; i < 10; i++) {
        reporter.captureMessage('Test $i');
      }

      final limitedReports = reporter.getReports(limit: 5);
      expect(limitedReports.length, 5);
    });

    test('should export reports as JSON', () {
      reporter.captureException(Exception('Test'));

      final json = reporter.exportReports();
      expect(json, isA<List>());
      expect(json.length, 1);
      expect(json.first['exception'], contains('Test'));
    });

    test('should clear all reports', () {
      reporter.captureMessage('Test 1');
      reporter.captureMessage('Test 2');
      
      expect(reporter.getReports().length, 2);
      
      reporter.clearReports();
      expect(reporter.getReports().length, 0);
    });

    test('should limit local report storage', () {
      // Exceed max local reports
      for (int i = 0; i < 150; i++) {
        reporter.captureMessage('Test $i');
      }

      final reports = reporter.getReports();
      expect(reports.length, lessThanOrEqualTo(100));
    });
  });

  group('CrashReport', () {
    test('should serialize to JSON', () {
      final report = CrashReport(
        id: 'test-123',
        timestamp: DateTime(2024, 1, 1),
        severity: ErrorSeverity.error,
        exception: Exception('Test'),
        context: {'key': 'value'},
      );

      final json = report.toJson();
      expect(json['id'], 'test-123');
      expect(json['severity'], 'error');
      expect(json['context']['key'], 'value');
    });
  });

  group('Error handling helpers', () {
    test('withErrorHandling should catch and report errors', () {
      final reporter = CrashReporter();
      reporter.clearReports();

      expect(
        () => withErrorHandling(() => throw Exception('Test error')),
        throwsA(isA<Exception>()),
      );

      final reports = reporter.getReports();
      expect(reports.length, 1);
      expect(reports.first.exception.toString(), contains('Test error'));
    });

    test('withErrorHandling should return result on success', () {
      final result = withErrorHandling(() => 42);
      expect(result, 42);
    });

    test('withErrorHandlingAsync should catch async errors', () async {
      final reporter = CrashReporter();
      reporter.clearReports();

      await expectLater(
        withErrorHandlingAsync(() async => throw Exception('Async error')),
        throwsA(isA<Exception>()),
      );

      final reports = reporter.getReports();
      expect(reports.length, 1);
    });

    test('withErrorHandlingAsync should return result on success', () async {
      final result = await withErrorHandlingAsync(() async => 42);
      expect(result, 42);
    });

    test('error handlers should include operation context', () {
      final reporter = CrashReporter();
      reporter.clearReports();

      expect(
        () => withErrorHandling(
          () => throw Exception('Test'),
          operation: 'test_operation',
          context: {'extra': 'data'},
        ),
        throwsA(isA<Exception>()),
      );

      final reports = reporter.getReports();
      expect(reports.first.context['operation'], 'test_operation');
      expect(reports.first.context['extra'], 'data');
    });
  });
}
