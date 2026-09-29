// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Crash reporting and error tracking service.
/// 
/// Captures uncaught exceptions, provides context,
/// and integrates with error reporting services.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Error severity levels
enum ErrorSeverity { fatal, error, warning, info, debug }

/// Crash report entry
class CrashReport {
  final String id;
  final DateTime timestamp;
  final ErrorSeverity severity;
  final dynamic exception;
  final StackTrace? stackTrace;
  final Map<String, dynamic> context;
  final String? userId;
  final String? sessionId;

  CrashReport({
    required this.id,
    required this.timestamp,
    required this.severity,
    required this.exception,
    this.stackTrace,
    this.context = const {},
    this.userId,
    this.sessionId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'severity': severity.name,
        'exception': exception.toString(),
        'stackTrace': stackTrace?.toString(),
        'context': context,
        'userId': userId,
        'sessionId': sessionId,
        'platform': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
      };
}

/// Crash reporter singleton
class CrashReporter {
  static final CrashReporter _instance = CrashReporter._internal();
  factory CrashReporter() => _instance;
  CrashReporter._internal();

  final List<CrashReport> _localReports = [];
  final int _maxLocalReports = 100;
  
  bool _isInitialized = false;
  String? _userId;
  String? _sessionId;
  Map<String, dynamic> _globalContext = {};

  /// Initialize crash reporting
  Future<void> initialize({
    String? userId,
    Map<String, dynamic>? context,
  }) async {
    if (_isInitialized) return;

    _userId = userId;
    _sessionId = _generateSessionId();
    _globalContext = context ?? {};
    
    // Set up Flutter error handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      captureException(
        details.exception,
        stackTrace: details.stack,
        severity: ErrorSeverity.error,
        context: {
          'library': details.library ?? 'unknown',
          'context': details.context?.toString(),
        },
      );
    };

    // Set up async error handler
    PlatformDispatcher.instance.onError = (error, stack) {
      captureException(
        error,
        stackTrace: stack,
        severity: ErrorSeverity.fatal,
      );
      return true;
    };

    _isInitialized = true;
    debugPrint('📊 Crash reporter initialized');
  }

  /// Capture an exception
  void captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    ErrorSeverity severity = ErrorSeverity.error,
    Map<String, dynamic>? context,
  }) {
    final report = CrashReport(
      id: _generateReportId(),
      timestamp: DateTime.now(),
      severity: severity,
      exception: exception,
      stackTrace: stackTrace,
      context: {..._globalContext, ...?context},
      userId: _userId,
      sessionId: _sessionId,
    );

    _localReports.add(report);
    
    // Limit local storage
    if (_localReports.length > _maxLocalReports) {
      _localReports.removeAt(0);
    }

    // Log to console in debug mode
    if (kDebugMode) {
      debugPrint('❌ Exception captured: $exception');
      if (stackTrace != null) {
        debugPrint('Stack trace:\n$stackTrace');
      }
    }

    // TODO: Send to crash reporting service (Sentry, Firebase Crashlytics, etc.)
    _sendToService(report);
  }

  /// Capture a message
  void captureMessage(
    String message, {
    ErrorSeverity severity = ErrorSeverity.info,
    Map<String, dynamic>? context,
  }) {
    captureException(
      message,
      severity: severity,
      context: context,
    );
  }

  /// Set user context
  void setUser(String? userId) {
    _userId = userId;
  }

  /// Set global context
  void setContext(String key, dynamic value) {
    _globalContext[key] = value;
  }

  /// Add breadcrumb (user action trail)
  void addBreadcrumb(String message, {Map<String, dynamic>? data}) {
    // TODO: Implement breadcrumb trail
    debugPrint('🍞 Breadcrumb: $message');
  }

  /// Get all local reports
  List<CrashReport> getReports({
    ErrorSeverity? minSeverity,
    int? limit,
  }) {
    var reports = _localReports;
    
    if (minSeverity != null) {
      final minIndex = ErrorSeverity.values.indexOf(minSeverity);
      reports = reports.where((r) {
        final index = ErrorSeverity.values.indexOf(r.severity);
        return index <= minIndex;
      }).toList();
    }
    
    if (limit != null && reports.length > limit) {
      reports = reports.sublist(reports.length - limit);
    }
    
    return reports;
  }

  /// Export reports as JSON
  List<Map<String, dynamic>> exportReports() {
    return _localReports.map((r) => r.toJson()).toList();
  }

  /// Clear local reports
  void clearReports() {
    _localReports.clear();
  }

  String _generateSessionId() {
    return '${DateTime.now().millisecondsSinceEpoch}-${_generateRandomString(8)}';
  }

  String _generateReportId() {
    return '${DateTime.now().millisecondsSinceEpoch}-${_generateRandomString(12)}';
  }

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (i) => chars[(DateTime.now().microsecond + i) % chars.length]).join();
  }

  Future<void> _sendToService(CrashReport report) async {
    // TODO: Implement integration with crash reporting service
    // Example: Sentry, Firebase Crashlytics, custom endpoint
    
    // For now, just log
    if (report.severity == ErrorSeverity.fatal || report.severity == ErrorSeverity.error) {
      debugPrint('📤 Would send crash report to service: ${report.id}');
    }
  }
}

/// Helper to wrap code with error handling
T withErrorHandling<T>(
  T Function() fn, {
  String? operation,
  Map<String, dynamic>? context,
}) {
  try {
    return fn();
  } catch (e, stack) {
    CrashReporter().captureException(
      e,
      stackTrace: stack,
      context: {
        if (operation != null) 'operation': operation,
        ...?context,
      },
    );
    rethrow;
  }
}

/// Async version
Future<T> withErrorHandlingAsync<T>(
  Future<T> Function() fn, {
  String? operation,
  Map<String, dynamic>? context,
}) async {
  try {
    return await fn();
  } catch (e, stack) {
    CrashReporter().captureException(
      e,
      stackTrace: stack,
      context: {
        if (operation != null) 'operation': operation,
        ...?context,
      },
    );
    rethrow;
  }
}
