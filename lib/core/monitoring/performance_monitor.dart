// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Application Performance Monitoring (APM) service.
/// 
/// Tracks performance metrics including:
/// - Operation latency
/// - Memory usage
/// - Frame rendering performance
/// - Network request timing

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Performance metric entry
class PerformanceMetric {
  final String name;
  final DateTime timestamp;
  final int durationMs;
  final Map<String, dynamic> attributes;

  PerformanceMetric({
    required this.name,
    required this.timestamp,
    required this.durationMs,
    this.attributes = const {},
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'timestamp': timestamp.toIso8601String(),
        'durationMs': durationMs,
        'attributes': attributes,
      };
}

/// Performance trace for tracking operations
class PerformanceTrace {
  final String name;
  final DateTime startTime;
  final Map<String, dynamic> attributes;
  final Stopwatch _stopwatch;

  PerformanceTrace(this.name, {this.attributes = const {}})
      : startTime = DateTime.now(),
        _stopwatch = Stopwatch()..start();

  /// Stop the trace and record metric
  PerformanceMetric stop() {
    _stopwatch.stop();
    return PerformanceMetric(
      name: name,
      timestamp: startTime,
      durationMs: _stopwatch.elapsedMilliseconds,
      attributes: attributes,
    );
  }

  /// Get elapsed time without stopping
  int get elapsedMs => _stopwatch.elapsedMilliseconds;
}

/// Frame timing statistics
class FrameStats {
  final int totalFrames;
  final int droppedFrames;
  final double averageFrameTime;
  final double p95FrameTime;
  final double p99FrameTime;
  final DateTime collectedAt;

  FrameStats({
    required this.totalFrames,
    required this.droppedFrames,
    required this.averageFrameTime,
    required this.p95FrameTime,
    required this.p99FrameTime,
    required this.collectedAt,
  });

  double get droppedFrameRate => 
      totalFrames > 0 ? (droppedFrames / totalFrames) * 100 : 0.0;

  Map<String, dynamic> toJson() => {
        'totalFrames': totalFrames,
        'droppedFrames': droppedFrames,
        'droppedFrameRate': droppedFrameRate,
        'averageFrameTime': averageFrameTime,
        'p95FrameTime': p95FrameTime,
        'p99FrameTime': p99FrameTime,
        'collectedAt': collectedAt.toIso8601String(),
      };
}

/// Memory usage snapshot
class MemorySnapshot {
  final int rssBytes;
  final int heapBytes;
  final DateTime timestamp;

  MemorySnapshot({
    required this.rssBytes,
    required this.heapBytes,
    required this.timestamp,
  });

  double get rssMB => rssBytes / (1024 * 1024);
  double get heapMB => heapBytes / (1024 * 1024);

  Map<String, dynamic> toJson() => {
        'rssBytes': rssBytes,
        'heapBytes': heapBytes,
        'rssMB': rssMB,
        'heapMB': heapMB,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Performance monitoring service
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  final List<PerformanceMetric> _metrics = [];
  final List<double> _frameTimes = [];
  final int _maxMetrics = 1000;
  final int _maxFrameSamples = 1000;

  bool _isMonitoring = false;
  Timer? _memoryCheckTimer;
  MemorySnapshot? _lastMemorySnapshot;

  /// Initialize performance monitoring
  void initialize() {
    if (_isMonitoring) return;

    _isMonitoring = true;

    // Monitor frame rendering
    if (!kIsWeb) {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTiming);
    }

    // Periodic memory snapshots
    _memoryCheckTimer = Timer.periodic(Duration(minutes: 5), (_) {
      _captureMemorySnapshot();
    });

    debugPrint('📊 Performance monitoring initialized');
  }

  /// Record a performance metric
  void recordMetric(PerformanceMetric metric) {
    _metrics.add(metric);

    // Limit storage
    if (_metrics.length > _maxMetrics) {
      _metrics.removeAt(0);
    }

    // Log slow operations
    if (metric.durationMs > 1000) {
      debugPrint('⚠️ Slow operation: ${metric.name} took ${metric.durationMs}ms');
    }
  }

  /// Start a performance trace
  PerformanceTrace startTrace(String name, {Map<String, dynamic>? attributes}) {
    return PerformanceTrace(name, attributes: attributes ?? {});
  }

  /// Measure a synchronous operation
  T measure<T>(String name, T Function() operation, {Map<String, dynamic>? attributes}) {
    final trace = startTrace(name, attributes: attributes);
    try {
      return operation();
    } finally {
      recordMetric(trace.stop());
    }
  }

  /// Measure an asynchronous operation
  Future<T> measureAsync<T>(
    String name,
    Future<T> Function() operation, {
    Map<String, dynamic>? attributes,
  }) async {
    final trace = startTrace(name, attributes: attributes);
    try {
      return await operation();
    } finally {
      recordMetric(trace.stop());
    }
  }

  /// Handle frame timing callbacks
  void _onFrameTiming(List<FrameTiming> timings) {
    for (final timing in timings) {
      final buildDuration = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterDuration = timing.rasterDuration.inMicroseconds / 1000.0;
      final totalDuration = buildDuration + rasterDuration;

      _frameTimes.add(totalDuration);

      // Limit samples
      if (_frameTimes.length > _maxFrameSamples) {
        _frameTimes.removeAt(0);
      }
    }
  }

  /// Get frame statistics
  FrameStats? getFrameStats() {
    if (_frameTimes.isEmpty) return null;

    final sortedTimes = List<double>.from(_frameTimes)..sort();
    final targetFrameTime = 16.67; // 60 FPS target

    final droppedFrames = _frameTimes.where((t) => t > targetFrameTime).length;
    final average = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
    final p95Index = (sortedTimes.length * 0.95).floor();
    final p99Index = (sortedTimes.length * 0.99).floor();

    return FrameStats(
      totalFrames: _frameTimes.length,
      droppedFrames: droppedFrames,
      averageFrameTime: average,
      p95FrameTime: sortedTimes[p95Index],
      p99FrameTime: sortedTimes[p99Index],
      collectedAt: DateTime.now(),
    );
  }

  /// Capture current memory usage
  Future<MemorySnapshot?> _captureMemorySnapshot() async {
    try {
      if (kIsWeb) return null;

      final info = ProcessInfo.currentRss;
      // Note: Dart doesn't expose heap size directly, using RSS as approximation
      
      final snapshot = MemorySnapshot(
        rssBytes: info,
        heapBytes: info, // Approximation
        timestamp: DateTime.now(),
      );

      _lastMemorySnapshot = snapshot;

      // Warn on high memory usage
      if (snapshot.rssMB > 500) {
        debugPrint('⚠️ High memory usage: ${snapshot.rssMB.toStringAsFixed(1)} MB');
      }

      return snapshot;
    } catch (e) {
      debugPrint('Failed to capture memory snapshot: $e');
      return null;
    }
  }

  /// Get current memory snapshot
  Future<MemorySnapshot?> getMemorySnapshot() async {
    return await _captureMemorySnapshot();
  }

  /// Get metrics by name
  List<PerformanceMetric> getMetrics(String name, {int? limit}) {
    var filtered = _metrics.where((m) => m.name == name).toList();
    
    if (limit != null && filtered.length > limit) {
      filtered = filtered.sublist(filtered.length - limit);
    }
    
    return filtered;
  }

  /// Get all metrics
  List<PerformanceMetric> getAllMetrics({int? limit}) {
    if (limit != null && _metrics.length > limit) {
      return _metrics.sublist(_metrics.length - limit);
    }
    return List.unmodifiable(_metrics);
  }

  /// Calculate average duration for an operation
  double? getAverageDuration(String name) {
    final metrics = _metrics.where((m) => m.name == name).toList();
    if (metrics.isEmpty) return null;

    final total = metrics.fold<int>(0, (sum, m) => sum + m.durationMs);
    return total / metrics.length;
  }

  /// Calculate percentile duration for an operation
  int? getPercentileDuration(String name, double percentile) {
    final metrics = _metrics.where((m) => m.name == name).toList();
    if (metrics.isEmpty) return null;

    final sorted = metrics.map((m) => m.durationMs).toList()..sort();
    final index = (sorted.length * percentile).floor();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  /// Export performance report
  Map<String, dynamic> exportReport() {
    final frameStats = getFrameStats();
    
    // Group metrics by name
    final metricsByName = <String, List<PerformanceMetric>>{};
    for (final metric in _metrics) {
      metricsByName.putIfAbsent(metric.name, () => []).add(metric);
    }

    final metricSummary = metricsByName.map((name, metrics) {
      final durations = metrics.map((m) => m.durationMs).toList()..sort();
      final avg = durations.reduce((a, b) => a + b) / durations.length;
      final p95Index = (durations.length * 0.95).floor();
      final p99Index = (durations.length * 0.99).floor();

      return MapEntry(name, {
        'count': metrics.length,
        'averageMs': avg,
        'p50Ms': durations[durations.length ~/ 2],
        'p95Ms': durations[p95Index],
        'p99Ms': durations[p99Index],
        'minMs': durations.first,
        'maxMs': durations.last,
      });
    });

    return {
      'timestamp': DateTime.now().toIso8601String(),
      'frameStats': frameStats?.toJson(),
      'memorySnapshot': _lastMemorySnapshot?.toJson(),
      'metrics': metricSummary,
      'totalMetrics': _metrics.length,
    };
  }

  /// Clear all metrics
  void clearMetrics() {
    _metrics.clear();
    _frameTimes.clear();
  }

  void dispose() {
    _memoryCheckTimer?.cancel();
    _isMonitoring = false;
    
    if (!kIsWeb) {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTiming);
    }
  }
}

/// Extension for easy performance tracking
extension PerformanceTrackingExtension on Future<T> Function() {
  Future<T> track(String name, {Map<String, dynamic>? attributes}) {
    return PerformanceMonitor().measureAsync(name, this, attributes: attributes);
  }
}
