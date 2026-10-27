// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../custom_source/domain/custom_source.dart';
import '../../custom_source/domain/custom_source_service.dart';
import 'media_probe.dart';
import 'source_check_report.dart';
import 'source_check_samples.dart';

/// 检测进度：界面上要显示「第几项 / 共几项」和当前在测什么。
@immutable
class SourceCheckProgress {
  const SourceCheckProgress({
    required this.done,
    required this.total,
    this.current = '',
    this.currentSourceId = '',
    this.reports = const <String, SourceCheckReport>{},
  });

  final int done;
  final int total;

  /// 形如 `tx · flac`，用于「正在测试：…」。
  final String current;
  final String currentSourceId;

  /// 已经跑完的脚本报告，边测边可见。
  final Map<String, SourceCheckReport> reports;

  double get fraction => total <= 0 ? 0 : done / total;
}

/// 跑一次完整的音源检测。
///
/// 流程对齐瓜子音乐的做法：每个平台用固定样本曲，对它声明的音质逐档取链；
/// 先给 8 秒，超时再放宽到 25 秒重试一次（命中算冷启动）；拿到地址后用 Range
/// 请求确认是音频、并估一下体积，明显小于样本曲时长对应的下限就判为试听片段。
class SourceCheckRunner {
  SourceCheckRunner({
    required this.service,
    MediaProbe? probe,
    Map<String, SourceCheckSample>? samples,
    this.firstTimeout = const Duration(seconds: 8),
    this.retryTimeout = const Duration(seconds: 25),
    this.qualitiesPerPlatform = 2,
  }) : probe = probe ?? HttpMediaProbe(),
       samples = samples ?? sourceCheckSamples;

  /// 取链走的是应用真实的脚本执行链路，检测结果才有意义。
  final CustomSourceService service;
  final MediaProbe probe;
  final Map<String, SourceCheckSample> samples;
  final Duration firstTimeout;
  final Duration retryTimeout;
  final int qualitiesPerPlatform;

  /// 样本曲时长对应的体积下限（约 64 kbps）。低于它基本是试听片段或人声提示音。
  static const int _minimumBytesPerSecond = 8000;

  /// 测一个脚本。脚本加载失败或一个平台都没声明时返回 null。
  Future<SourceCheckReport?> runScript(
    CustomSource source, {
    bool Function()? isCancelled,
    void Function(SourceCheckProgress)? onProgress,
    Map<String, SourceCheckReport> done = const <String, SourceCheckReport>{},
  }) async {
    final cancelled = isCancelled ?? () => false;
    final capabilities = await service.capabilitiesOf(source.id);
    if (capabilities == null) return null;

    final declared = capabilities.platformsFor('musicUrl');
    final tested = declared.where(samples.containsKey).toList(growable: false);
    final skipped = declared.where((p) => !samples.containsKey(p)).toList(
      growable: false,
    );
    if (tested.isEmpty) {
      return SourceCheckReport(
        sourceId: source.id,
        sourceName: source.name,
        perPlatform: const {},
        testedAt: DateTime.now(),
        skippedPlatforms: skipped,
      );
    }

    // 每个平台实际要测的音质：声明的按高→低排序，最多测 [qualitiesPerPlatform] 档；
    // 一档都没声明时测「默认音质」（空串）。
    final plan = <String, List<String>>{};
    var total = 0;
    for (final platform in tested) {
      final declaredQualities = capabilities.qualitiesFor(
        platform,
        sourceCheckQualityOrder,
      );
      final qualities = declaredQualities.isEmpty
          ? const ['']
          : declaredQualities.take(qualitiesPerPlatform).toList(growable: false);
      plan[platform] = qualities;
      total += qualities.length;
    }

    var doneItems = 0;
    final perPlatform = <String, SourceCheckPlatformReport>{};
    onProgress?.call(
      SourceCheckProgress(
        done: 0,
        total: total,
        current: '',
        currentSourceId: source.id,
        reports: done,
      ),
    );

    for (final platform in tested) {
      if (cancelled()) break;
      final sample = samples[platform]!;
      final qualities = <String, SourceCheckResult>{};
      for (final quality in plan[platform]!) {
        if (cancelled()) break;
        onProgress?.call(
          SourceCheckProgress(
            done: doneItems,
            total: total,
            current: '$platform · ${quality.isEmpty ? 'default' : quality}',
            currentSourceId: source.id,
            reports: done,
          ),
        );
        qualities[quality] = await _checkOne(
          source: source,
          platform: platform,
          quality: quality,
          sample: sample,
        );
        doneItems++;
        onProgress?.call(
          SourceCheckProgress(
            done: doneItems,
            total: total,
            current: '$platform · ${quality.isEmpty ? 'default' : quality}',
            currentSourceId: source.id,
            reports: done,
          ),
        );
      }
      if (qualities.isNotEmpty) {
        perPlatform[platform] = SourceCheckPlatformReport(
          platform: platform,
          qualities: qualities,
          testedAt: DateTime.now(),
        );
      }
    }

    return SourceCheckReport(
      sourceId: source.id,
      sourceName: source.name,
      perPlatform: perPlatform,
      testedAt: DateTime.now(),
      skippedPlatforms: skipped,
    );
  }

  /// 依次测多个脚本；单个脚本失败不影响后面的。
  Future<List<SourceCheckReport>> runAll(
    List<CustomSource> sources, {
    bool Function()? isCancelled,
    void Function(SourceCheckProgress)? onProgress,
  }) async {
    final cancelled = isCancelled ?? () => false;
    final reports = <String, SourceCheckReport>{};
    final finished = <SourceCheckReport>[];
    for (final source in sources) {
      if (cancelled()) break;
      final report = await runScript(
        source,
        isCancelled: cancelled,
        onProgress: onProgress,
        done: Map<String, SourceCheckReport>.from(reports),
      );
      if (report != null) {
        reports[source.id] = report;
        finished.add(report);
      }
    }
    return finished;
  }

  Future<SourceCheckResult> _checkOne({
    required CustomSource source,
    required String platform,
    required String quality,
    required SourceCheckSample sample,
  }) async {
    final stopwatch = Stopwatch()..start();
    final requestedQuality = quality.isEmpty ? '320k' : quality;
    var coldStart = false;

    ({String url, String? type})? detailed;
    try {
      detailed = await _fetch(source, sample, requestedQuality).timeout(
        firstTimeout,
      );
    } on TimeoutException {
      // 冷启动很常见：第一次调用要建连接、跑脚本里的初始化。放宽一次再判死。
      try {
        detailed = await _fetch(source, sample, requestedQuality).timeout(
          retryTimeout,
        );
        coldStart = true;
      } on TimeoutException {
        stopwatch.stop();
        return SourceCheckResult(
          platform: platform,
          quality: quality,
          verdict: SourceCheckVerdict.softFail,
          latencyMs: stopwatch.elapsedMilliseconds,
          message: '取链接超时（8 秒 + 25 秒重试均未返回）',
        );
      } catch (error) {
        stopwatch.stop();
        return _hardFail(platform, quality, error, stopwatch.elapsedMilliseconds);
      }
    } catch (error) {
      stopwatch.stop();
      return _hardFail(platform, quality, error, stopwatch.elapsedMilliseconds);
    }

    final url = detailed?.url;
    if (url == null || url.isEmpty) {
      stopwatch.stop();
      return SourceCheckResult(
        platform: platform,
        quality: quality,
        verdict: SourceCheckVerdict.hardFail,
        latencyMs: stopwatch.elapsedMilliseconds,
        message: '脚本没有返回播放地址',
      );
    }

    final probed = await probe.probe(url, platform: platform);
    stopwatch.stop();
    final latency = stopwatch.elapsedMilliseconds;
    if (!probed.ok) {
      return SourceCheckResult(
        platform: platform,
        quality: quality,
        verdict: probed.timedOut
            ? SourceCheckVerdict.softFail
            : SourceCheckVerdict.hardFail,
        latencyMs: latency,
        message: probed.message,
      );
    }

    final minimumBytes =
        sample.duration.inSeconds * _minimumBytesPerSecond;
    final size = probed.sizeBytes;
    if (size != null && minimumBytes > 0 && size < minimumBytes) {
      final sizeMb = (size / (1024 * 1024)).toStringAsFixed(1);
      final minutes = (sample.duration.inSeconds / 60).round();
      return SourceCheckResult(
        platform: platform,
        quality: quality,
        verdict: SourceCheckVerdict.hardFail,
        latencyMs: latency,
        sizeBytes: size,
        extension: probed.extension,
        message: '文件仅 $sizeMb MB（样本曲约 $minutes 分钟），疑似试听片段或防盗链语音',
      );
    }

    return SourceCheckResult(
      platform: platform,
      quality: quality,
      verdict: SourceCheckVerdict.ok,
      latencyMs: latency,
      sizeBytes: size,
      extension: probed.extension,
      coldStart: coldStart,
      message: coldStart ? '可用（首次较慢，疑似冷启动）' : '',
    );
  }

  Future<({String url, String? type})?> _fetch(
    CustomSource source,
    SourceCheckSample sample,
    String quality,
  ) {
    return service.getMusicUrlDetailed(
      source.id,
      sample.toMusicItem(source.id),
      quality: quality,
      requireEnabled: false,
    );
  }

  SourceCheckResult _hardFail(
    String platform,
    String quality,
    Object error,
    int latencyMs,
  ) {
    var message = error.toString();
    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }
    if (message.length > 160) message = '${message.substring(0, 160)}…';
    return SourceCheckResult(
      platform: platform,
      quality: quality,
      verdict: SourceCheckVerdict.hardFail,
      latencyMs: latencyMs,
      message: message,
    );
  }
}
