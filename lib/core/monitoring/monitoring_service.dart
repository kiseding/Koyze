// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Unified monitoring configuration and initialization.
/// 
/// Provides a single entry point to initialize all monitoring services:
/// - Source health monitoring
/// - Crash reporting
/// - Performance monitoring

import 'package:flutter/foundation.dart';
import 'source_health_monitor.dart';
import 'crash_reporter.dart';
import 'performance_monitor.dart';

class MonitoringConfig {
  final bool enableHealthMonitoring;
  final bool enableCrashReporting;
  final bool enablePerformanceMonitoring;
  final String? userId;
  final Map<String, dynamic> globalContext;

  const MonitoringConfig({
    this.enableHealthMonitoring = true,
    this.enableCrashReporting = true,
    this.enablePerformanceMonitoring = true,
    this.userId,
    this.globalContext = const {},
  });

  /// Production configuration
  static const production = MonitoringConfig(
    enableHealthMonitoring: true,
    enableCrashReporting: true,
    enablePerformanceMonitoring: true,
  );

  /// Development configuration (minimal monitoring)
  static const development = MonitoringConfig(
    enableHealthMonitoring: false,
    enableCrashReporting: true,
    enablePerformanceMonitoring: false,
  );

  /// Disabled (for testing)
  static const disabled = MonitoringConfig(
    enableHealthMonitoring: false,
    enableCrashReporting: false,
    enablePerformanceMonitoring: false,
  );
}

class MonitoringService {
  static final MonitoringService _instance = MonitoringService._internal();
  factory MonitoringService() => _instance;
  MonitoringService._internal();

  SourceHealthMonitor? _healthMonitor;
  CrashReporter? _crashReporter;
  PerformanceMonitor? _performanceMonitor;

  bool _isInitialized = false;
  MonitoringConfig? _config;

  /// Initialize all monitoring services
  Future<void> initialize(MonitoringConfig config) async {
    if (_isInitialized) {
      debugPrint('⚠️ Monitoring already initialized');
      return;
    }

    _config = config;

    // 1. Initialize crash reporting first (to catch early errors)
    if (config.enableCrashReporting) {
      _crashReporter = CrashReporter();
      await _crashReporter!.initialize(
        userId: config.userId,
        context: {
          ...config.globalContext,
          'environment': kDebugMode ? 'debug' : 'release',
        },
      );
      debugPrint('✅ Crash reporting initialized');
    }

    // 2. Initialize performance monitoring
    if (config.enablePerformanceMonitoring) {
      _performanceMonitor = PerformanceMonitor();
      _performanceMonitor!.initialize();
      debugPrint('✅ Performance monitoring initialized');
    }

    // 3. Initialize health monitoring
    if (config.enableHealthMonitoring) {
      _healthMonitor = SourceHealthMonitor();
      _healthMonitor!.startMonitoring();
      debugPrint('✅ Health monitoring initialized');
    }

    _isInitialized = true;
    debugPrint('🎉 All monitoring services initialized');
  }

  /// Get health monitor instance
  SourceHealthMonitor? get healthMonitor => _healthMonitor;

  /// Get crash reporter instance
  CrashReporter? get crashReporter => _crashReporter;

  /// Get performance monitor instance
  PerformanceMonitor? get performanceMonitor => _performanceMonitor;

  /// Check if monitoring is enabled
  bool get isMonitoringEnabled => _isInitialized;

  /// Update user context across all services
  void setUser(String? userId) {
    _crashReporter?.setUser(userId);
  }

  /// Export comprehensive monitoring report
  Map<String, dynamic> exportFullReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'isInitialized': _isInitialized,
      'config': {
        'healthMonitoring': _config?.enableHealthMonitoring,
        'crashReporting': _config?.enableCrashReporting,
        'performanceMonitoring': _config?.enablePerformanceMonitoring,
      },
      'health': _healthMonitor?.exportHealthReport(),
      'crashes': _crashReporter?.exportReports(),
      'performance': _performanceMonitor?.exportReport(),
    };
  }

  /// Dispose all monitoring services
  void dispose() {
    _healthMonitor?.dispose();
    _performanceMonitor?.dispose();
    _isInitialized = false;
    debugPrint('🛑 All monitoring services disposed');
  }
}

/// Extension for easy monitoring access in the app
extension MonitoringExtension on Object {
  /// Track an operation with performance monitoring
  T tracked<T>(String name, T Function() operation) {
    final monitor = MonitoringService().performanceMonitor;
    if (monitor == null) return operation();
    return monitor.measure(name, operation);
  }

  /// Track an async operation
  Future<T> trackedAsync<T>(String name, Future<T> Function() operation) async {
    final monitor = MonitoringService().performanceMonitor;
    if (monitor == null) return await operation();
    return await monitor.measureAsync(name, operation);
  }
}
