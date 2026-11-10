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

import '../logging/app_log.dart';
import 'debug_probe.dart';

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
  bool _listeningToFrames = false;
  Timer? _memoryCheckTimer;
  Timer? _frameSummaryTimer;
  MemorySnapshot? _lastMemorySnapshot;

  /// 当前统计窗口内的分段耗时。帧率本身说明不了问题——掉帧要看是 UI 线程
  /// 超预算（build）还是 GPU 超预算（raster），改的地方完全不同。
  final List<double> _windowBuild = <double>[];
  final List<double> _windowRaster = <double>[];
  final List<double> _windowTotal = <double>[];

  /// 连续「明显卡顿」的窗口数，用来给日志加一个严重程度。
  int _stutterStreak = 0;
  DateTime? _lastStutterLoggedAt;

  /// 掉帧率超过这个比例才记录。
  ///
  /// 设置页滑一下、列表惯性滚动，偶尔夹一两帧 17ms 是常态；把这些都写进
  /// 日志会把真正的问题淹掉。25% 意味着「四帧里至少掉一帧」，用户已经能
  /// 明显感到不跟手了。
  static const double _stutterDroppedRatio = 0.25;

  /// 最差单帧超过这个毫秒数也算明显卡顿——哪怕整体掉帧率不高，一次 80ms
  /// 的停顿（一次同步 IO、一次大图解码）主观上就是一个「卡住」。
  static const double _stutterWorstMs = 48;

  /// 同一个窗口连续上报的最小间隔，避免一段长卡顿每 2 秒刷一条。
  static const Duration _stutterLogInterval = Duration(seconds: 6);

  SchedulerBinding? _schedulerBindingOrNull() {
    try {
      return SchedulerBinding.instance;
    } on Object {
      return null;
    }
  }

  /// Initialize performance monitoring
  void initialize() {
    if (_isMonitoring) return;

    _isMonitoring = true;

    // 帧探针只在明确打开时才接线（见 DebugProbe）：帧回调与 2 秒汇总定时器
    // 对正常用户没有任何产出，却要一直付调度开销。
    if (DebugProbe.enabled) startFrameProbe();

    // Periodic memory snapshots
    _memoryCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _captureMemorySnapshot();
    });

    debugPrint(
      '📊 Performance monitoring initialized '
      '(frame probe: ${DebugProbe.describe()})',
    );
  }

  /// 帧探针是否正在采集。
  bool get frameProbeRunning => _listeningToFrames;

  /// 打开帧探针。诊断面板打开、或设置里手动开启时调用；可重复调用。
  void startFrameProbe() {
    if (_listeningToFrames) return;
    final scheduler = kIsWeb ? null : _schedulerBindingOrNull();
    if (scheduler == null) return;
    scheduler.addTimingsCallback(_onFrameTiming);
    _listeningToFrames = true;
    // 每 2 秒把这一窗口的帧耗时写进运行日志。AppLog 只在诊断面板打开时
    // 真正记录，所以面板没开时也只是一次内存里的百分位计算。
    _frameSummaryTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      _flushFrameWindow();
    });
  }

  /// 关闭帧探针，并清掉未汇总的样本。
  void stopFrameProbe() {
    _frameSummaryTimer?.cancel();
    _frameSummaryTimer = null;
    if (_listeningToFrames) {
      _schedulerBindingOrNull()?.removeTimingsCallback(_onFrameTiming);
      _listeningToFrames = false;
    }
    _stutterStreak = 0;
    _lastStutterLoggedAt = null;
    _clearFrameWindow();
  }

  /// 输出并清空当前窗口的帧统计。
  ///
  /// **只在明显卡顿时写日志。** 诊断面板一开就是几分钟，每 2 秒一条
  /// `frames=120 build_p50=3.1 …` 会把用户真正关心的错误挤到屏幕外，也没人
  /// 会去读「一切正常」的那几十行。所以这里先判一次「这一窗是不是真的卡」：
  ///
  /// * 掉帧率 ≥ 25%（四帧掉一帧，已经明显不跟手），或
  /// * 最差单帧 ≥ 48ms（一次可以感知到的停顿）；
  ///
  /// 两条都不满足就什么都不写。连续卡顿的窗口会带上 `streak=N`，并且最多
  /// 每 6 秒记一条，避免一段持续卡顿把日志刷满。
  ///
  /// 探针本身（[startFrameProbe]）依然每 2 秒跑一次，只是绝大多数窗口不会
  /// 产生日志——这也正是「启用期间包含帧率诊断」与「不然记录太多」之间的
  /// 平衡点。
  void _flushFrameWindow() {
    if (_windowTotal.length < 8) {
      // 空闲期的零星帧没有参考价值。
      _clearFrameWindow();
      return;
    }
    var dropped = 0;
    var worst = 0.0;
    for (final total in _windowTotal) {
      if (total > _budgetMs) dropped++;
      if (total > worst) worst = total;
    }
    final ratio = dropped / _windowTotal.length;
    final stutters = ratio >= _stutterDroppedRatio || worst >= _stutterWorstMs;
    if (!stutters) {
      // 这一段是流畅的：清掉连击，下次卡顿重新计数。
      _stutterStreak = 0;
      _clearFrameWindow();
      return;
    }

    _stutterStreak++;
    final now = DateTime.now();
    final last = _lastStutterLoggedAt;
    final throttled =
        last != null && now.difference(last) < _stutterLogInterval;
    if (!throttled) {
      _lastStutterLoggedAt = now;
      final summary =
          'frames=${_windowTotal.length} '
          'dropped=$dropped (${(ratio * 100).round()}%) '
          'worst=${worst.toStringAsFixed(1)}ms '
          'build_p50=${_percentile(_windowBuild, 0.5)} '
          'build_p95=${_percentile(_windowBuild, 0.95)} '
          'raster_p50=${_percentile(_windowRaster, 0.5)} '
          'raster_p95=${_percentile(_windowRaster, 0.95)} '
          'streak=$_stutterStreak';
      AppLog.instance.record(
        'perf',
        'jank $summary',
        // 单帧 80ms 以上、或已经连续卡了三窗，多半是用户能明确抱怨的程度，
        // 标成 warning 让诊断面板的黄色过滤能直接筛出来。
        level: (worst >= 80 || _stutterStreak >= 3)
            ? AppLogLevel.warning
            : AppLogLevel.info,
      );
      if (!kReleaseMode) debugPrint('FRAMEPROBE $summary');
    }
    _clearFrameWindow();
  }

  void _clearFrameWindow() {
    _windowBuild.clear();
    _windowRaster.clear();
    _windowTotal.clear();
  }

  static const double _budgetMs = 16.7;

  static String _percentile(List<double> samples, double quantile) {
    if (samples.isEmpty) return '0.0';
    final sorted = List<double>.of(samples)..sort();
    final index = ((sorted.length - 1) * quantile).round().clamp(
      0,
      sorted.length - 1,
    );
    return sorted[index].toStringAsFixed(1);
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
      debugPrint(
        '⚠️ Slow operation: ${metric.name} took ${metric.durationMs}ms',
      );
    }
  }

  /// Start a performance trace
  PerformanceTrace startTrace(String name, {Map<String, dynamic>? attributes}) {
    return PerformanceTrace(name, attributes: attributes ?? {});
  }

  /// Measure a synchronous operation
  T measure<T>(
    String name,
    T Function() operation, {
    Map<String, dynamic>? attributes,
  }) {
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

      _windowBuild.add(buildDuration);
      _windowRaster.add(rasterDuration);
      _windowTotal.add(totalDuration);

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
        debugPrint(
          '⚠️ High memory usage: ${snapshot.rssMB.toStringAsFixed(1)} MB',
        );
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
    stopFrameProbe();
    _isMonitoring = false;
  }
}

/// Extension for easy performance tracking
extension PerformanceTrackingExtension<T> on Future<T> Function() {
  Future<T> track(String name, {Map<String, dynamic>? attributes}) {
    return PerformanceMonitor().measureAsync(
      name,
      this,
      attributes: attributes,
    );
  }
}
