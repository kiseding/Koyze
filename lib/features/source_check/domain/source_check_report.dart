// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/foundation.dart';

/// 单次（脚本 × 平台 × 音质）检测的结论。
enum SourceCheckVerdict {
  /// 取到地址并且能读出音频内容。
  ok,

  /// 超时之类「不一定是脚本坏了」的失败：可能是冷启动。播放时排到最后，不跳过。
  softFail,

  /// 明确失败：脚本报错、没给地址、返回的不是音频、体积明显偏小。
  hardFail,
}

/// 把 [SourceCheckVerdict] 编成稳定的字符串，落盘后仍能读回。
String verdictToToken(SourceCheckVerdict verdict) => switch (verdict) {
  SourceCheckVerdict.ok => 'ok',
  SourceCheckVerdict.softFail => 'soft',
  SourceCheckVerdict.hardFail => 'hard',
};

SourceCheckVerdict verdictFromToken(String? token) => switch (token) {
  'ok' => SourceCheckVerdict.ok,
  'soft' => SourceCheckVerdict.softFail,
  _ => SourceCheckVerdict.hardFail,
};

/// 一条检测结果。
@immutable
class SourceCheckResult {
  const SourceCheckResult({
    required this.platform,
    required this.quality,
    required this.verdict,
    required this.latencyMs,
    this.sizeBytes,
    this.message = '',
    this.coldStart = false,
    this.extension,
  });

  final String platform;

  /// 脚本没有声明音质时为空串，界面上显示「默认音质」。
  final String quality;

  final SourceCheckVerdict verdict;
  final int latencyMs;
  final int? sizeBytes;
  final String message;

  /// 首次超时、放宽到 25 秒才成功，多半是冷启动。
  final bool coldStart;

  /// 从文件头嗅出来的扩展名，例如 `.flac`。
  final String? extension;

  bool get ok => verdict == SourceCheckVerdict.ok;

  double? get sizeMb =>
      sizeBytes == null ? null : sizeBytes! / (1024 * 1024);

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'quality': quality,
    'verdict': verdictToToken(verdict),
    'latencyMs': latencyMs,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    if (message.isNotEmpty) 'message': message,
    if (coldStart) 'coldStart': coldStart,
    if (extension != null) 'extension': extension,
  };

  factory SourceCheckResult.fromJson(Map<String, dynamic> json) {
    return SourceCheckResult(
      platform: json['platform']?.toString() ?? '',
      quality: json['quality']?.toString() ?? '',
      verdict: verdictFromToken(json['verdict']?.toString()),
      latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      message: json['message']?.toString() ?? '',
      coldStart: json['coldStart'] == true,
      extension: json['extension']?.toString(),
    );
  }
}

/// 一个脚本在某个平台上的全部音质结果。
@immutable
class SourceCheckPlatformReport {
  const SourceCheckPlatformReport({
    required this.platform,
    required this.qualities,
    required this.testedAt,
  });

  final String platform;

  /// key 是音质标识，未声明音质时是空串。
  final Map<String, SourceCheckResult> qualities;

  final DateTime testedAt;

  bool get tested => qualities.isNotEmpty;

  bool get anyOk =>
      qualities.values.any((r) => r.verdict == SourceCheckVerdict.ok);

  bool get anySoft =>
      qualities.values.any((r) => r.verdict == SourceCheckVerdict.softFail);

  /// 声明的音质全部明确失败 —— 播放这个平台时可以跳过这个脚本。
  bool get allHardFail => tested && !anyOk && !anySoft;

  /// 没有成功，但至少有一档只是超时 —— 排到最后而不是跳过。
  bool get hasSoftFail => tested && !anyOk && anySoft;

  /// 最快的可用音质延迟，用于在「都可用」时排序。
  int? get bestLatencyMs {
    final ok = qualities.values
        .where((r) => r.verdict == SourceCheckVerdict.ok)
        .map((r) => r.latencyMs)
        .toList(growable: false);
    return ok.isEmpty ? null : (ok..sort()).first;
  }

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'testedAt': testedAt.toIso8601String(),
    'qualities': qualities.map((key, value) => MapEntry(key, value.toJson())),
  };

  factory SourceCheckPlatformReport.fromJson(Map<String, dynamic> json) {
    final raw = json['qualities'];
    final qualities = <String, SourceCheckResult>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          qualities[entry.key.toString()] = SourceCheckResult.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    return SourceCheckPlatformReport(
      platform: json['platform']?.toString() ?? '',
      qualities: qualities,
      testedAt:
          DateTime.tryParse(json['testedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 一份脚本检测报告。
@immutable
class SourceCheckReport {
  const SourceCheckReport({
    required this.sourceId,
    required this.sourceName,
    required this.perPlatform,
    required this.testedAt,
    this.skippedPlatforms = const <String>[],
  });

  final String sourceId;
  final String sourceName;
  final Map<String, SourceCheckPlatformReport> perPlatform;
  final DateTime testedAt;

  /// 脚本声明了、但没有样本曲因此没测的平台。
  final List<String> skippedPlatforms;

  SourceCheckPlatformReport? forPlatform(String platform) =>
      perPlatform[platform];

  int get okPlatformCount =>
      perPlatform.values.where((report) => report.anyOk).length;

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'sourceName': sourceName,
    'testedAt': testedAt.toIso8601String(),
    if (skippedPlatforms.isNotEmpty) 'skippedPlatforms': skippedPlatforms,
    'perPlatform': perPlatform.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  factory SourceCheckReport.fromJson(Map<String, dynamic> json) {
    final raw = json['perPlatform'];
    final perPlatform = <String, SourceCheckPlatformReport>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          perPlatform[entry.key.toString()] = SourceCheckPlatformReport.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    final skipped = json['skippedPlatforms'];
    return SourceCheckReport(
      sourceId: json['sourceId']?.toString() ?? '',
      sourceName: json['sourceName']?.toString() ?? '',
      perPlatform: perPlatform,
      testedAt:
          DateTime.tryParse(json['testedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      skippedPlatforms: skipped is List
          ? skipped.map((value) => value.toString()).toList(growable: false)
          : const <String>[],
    );
  }
}

/// 全部脚本的检测结果，按脚本 id 索引。
@immutable
class SourceCheckBook {
  const SourceCheckBook({this.bySource = const <String, SourceCheckReport>{}});

  final Map<String, SourceCheckReport> bySource;

  static const empty = SourceCheckBook();

  bool get isEmpty => bySource.isEmpty;

  bool get isNotEmpty => bySource.isNotEmpty;

  SourceCheckReport? forSource(String sourceId) => bySource[sourceId];

  SourceCheckBook withReport(SourceCheckReport report) => SourceCheckBook(
    bySource: {...bySource, report.sourceId: report},
  );

  /// 脚本被删除或重装后清掉旧结果，避免用过期结论选源。
  SourceCheckBook retainOnly(Iterable<String> sourceIds) {
    final keep = sourceIds.toSet();
    final next = <String, SourceCheckReport>{};
    for (final entry in bySource.entries) {
      if (keep.contains(entry.key)) next[entry.key] = entry.value;
    }
    return next.length == bySource.length
        ? this
        : SourceCheckBook(bySource: next);
  }

  Map<String, dynamic> toJson() => {
    'sources': bySource.map((key, value) => MapEntry(key, value.toJson())),
  };

  factory SourceCheckBook.fromJson(Map<String, dynamic> json) {
    final raw = json['sources'];
    final bySource = <String, SourceCheckReport>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          bySource[entry.key.toString()] = SourceCheckReport.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    return SourceCheckBook(bySource: bySource);
  }
}
