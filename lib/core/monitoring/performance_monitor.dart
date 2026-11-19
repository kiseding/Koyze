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

  /// 最差单帧超过「几倍预算」就算明显卡顿。
  ///
  /// 用**倍数**而不是绝对毫秒数，是因为预算本身随刷新率变：60Hz 是 16.7ms，
  /// 120Hz（iPhone ProMotion，本项目 plist 已开满帧）只有 8.3ms。写死 48ms
  /// 在 60Hz 上相当于 3 帧、在 120Hz 上相当于 6 帧——同一个阈值在两台机器上
  /// 敏感度差一倍，长帧在 120Hz 上会被系统性地漏报。3 倍是「用户一定能看到
  /// 一次停顿」的量级。
  static const double _stutterWorstBudgetFactor = 3;

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
    if (DebugProbe.enabled) {
      startFrameProbe();
      // 探针包的用途是「让用户正常用一次，把那一瞬间的数据留住」。
      //
      // AppLog 默认只在诊断面板打开期间采集（见 app_log.dart 的 start/stop），
      // 而面板一关就停——那恰好漏掉面板关着时发生的卡顿，也就是用户真正抱怨
      // 的那一次。探针包里全程采集，用户滑完再打开面板就能看到 jank 摘要。
      //
      // installHooks 必须为 false：接管 debugPrint 会把框架的海量输出灌进
      // record()，而它每次都 List.unmodifiable 全量复制一遍条目——那等于让
      // 测量工具自己制造卡顿。这里只留显式 record() 的条目。
      AppLog.instance.start(installHooks: false);
    }

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
    // 判「掉帧」只看 build 与 raster **各自**有没有超预算，不看两者之和。
    //
    // 这里踩过一个很误导人的坑：早先是用 `build + raster > 16.7ms` 计的，
    // 于是「raster 15.6ms + build 0.6ms = 16.2ms」这种其实稳稳跑满 60fps 的
    // 帧，会在抖动几毫秒后被算成掉帧，日志里报出 37%~56% 的掉帧率——而同一
    // 窗口里 worst 只有 18.8ms，根本没有任何用户能感知的停顿。
    //
    // 原因在引擎的流水线：build 跑 UI 线程、raster 跑光栅线程，两者**跨帧**
    // 重叠——光栅第 N 帧时 UI 线程已经在建第 N+1 帧。所以一帧的吞吐成本是
    // max(build, raster)，不是和。Flutter 自己的 DevTools 也是分开看这两条
    // 时间线，任一条超预算才标红。相加只会把「本来就该占满一帧的 raster」
    // 冤成掉帧。
    // 预算按屏幕实际刷新率算：60Hz=16.7ms，120Hz=8.3ms。
    final budget = _effectiveBudgetMs;
    var dropped = 0;
    var worst = 0.0;
    // worst 只记「哪一帧最贵」，不说是 build 还是 raster。窗口里只有一个离群
    // 帧时 p95 常常取不到它（26 帧的 p95 是第 25 个值），于是日志上看着一切
    // 正常、却有个几百毫秒的 worst 对不上账。两个最大值分开记，一眼能判方向。
    var worstBuild = 0.0;
    var worstRaster = 0.0;
    for (var i = 0; i < _windowBuild.length; i++) {
      final build = _windowBuild[i];
      final raster = _windowRaster[i];
      // 一帧的实际成本：两条流水线里更忙的那条。
      final cost = build > raster ? build : raster;
      if (build > budget || raster > budget) dropped++;
      if (cost > worst) worst = cost;
      if (build > worstBuild) worstBuild = build;
      if (raster > worstRaster) worstRaster = raster;
    }
    final ratio = dropped / _windowBuild.length;
    final stutters =
        ratio >= _stutterDroppedRatio ||
        worst >= budget * _stutterWorstBudgetFactor;
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
          'frames=${_windowBuild.length} '
          'budget=${budget.toStringAsFixed(1)}ms '
          'dropped=$dropped (${(ratio * 100).round()}%) '
          'worst=${worst.toStringAsFixed(1)}ms '
          'worst_build=${worstBuild.toStringAsFixed(1)}ms '
          'worst_raster=${worstRaster.toStringAsFixed(1)}ms '
          'build_p50=${_percentile(_windowBuild, 0.5)} '
          'build_p95=${_percentile(_windowBuild, 0.95)} '
          'raster_p50=${_percentile(_windowRaster, 0.5)} '
          'raster_p95=${_percentile(_windowRaster, 0.95)} '
          'streak=$_stutterStreak';
      AppLog.instance.record(
        'perf',
        'jank $summary',
        // 单帧超过 5 倍预算（60Hz 下约 84ms、120Hz 下约 42ms）、或已经连续
        // 卡了三窗，多半是用户能明确抱怨的程度，标成 warning 让诊断面板的
        // 黄色过滤能直接筛出来。
        level: (worst >= budget * 5 || _stutterStreak >= 3)
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

  /// 当前生效的帧预算（毫秒），随屏幕刷新率变化。
  ///
  /// 60Hz → 16.7ms；120Hz（iPhone ProMotion，本项目 plist 开了满帧）→ 8.3ms。
  /// 暴露出来是为了让测试能锁住这条换算，也方便诊断面板显示"这一刻的预算
  /// 到底是多少"——否则在 120Hz 机器上看到 15ms 的 raster 无法判断超没超。
  @visibleForTesting
  double get effectiveBudgetMs => _effectiveBudgetMs;

  /// 当前窗口实际要满足的帧预算。
  ///
  /// 60Hz 是 16.7ms，但 iPhone 开了 `CADisableMinimumFrameDurationOnPhone`
  /// （本项目 ios/Runner/Info.plist 就是开的）之后，ProMotion 屏会跑 120Hz，
  /// 预算变成 8.3ms。同一份 raster 15ms 的脚本，在 60Hz 上刚好及格、在 120Hz
  /// 上就是每帧都超——用户看到的"滑动卡顿"很可能就是这个差值造成的。
  ///
  /// 日志里必须把预算一起写出来，否则在 120Hz 机器上读到的 15ms 无法判断
  /// 到底超没超。
  double get _effectiveBudgetMs {
    final scheduler = _schedulerBindingOrNull();
    if (scheduler == null) return _budgetMs;
    final views = scheduler.platformDispatcher.views;
    if (views.isEmpty) return _budgetMs;
    final refreshRate = views.first.display.refreshRate;
    if (refreshRate <= 0) return _budgetMs;
    return 1000.0 / refreshRate;
  }

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
      // 单帧成本取两条流水线里更忙的那条，**不是**两者之和。
      // build 在 UI 线程、raster 在光栅线程，跨帧并行；相加会把「该占满一帧
      // 的 raster」累加成假掉帧（详见 _flushFrameWindow 里的说明）。
      final frameCost = buildDuration > rasterDuration
          ? buildDuration
          : rasterDuration;

      _frameTimes.add(frameCost);

      _windowBuild.add(buildDuration);
      _windowRaster.add(rasterDuration);
      _windowTotal.add(frameCost);

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
    // 与 _flushFrameWindow 用同一个预算：扣着实际刷新率走，别写死 60Hz。
    final targetFrameTime = _effectiveBudgetMs;

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
