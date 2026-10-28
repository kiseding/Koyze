// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/foundation.dart';

/// 多长时间重复一次。
///
/// 只做这三种：这已经覆盖了「每天早上推首歌」「工作日提醒换歌单」
/// 「每周日整理上周歌单」。更复杂的 cron 表达在这类应用里没人愿意填。
enum AiScheduleCadence { daily, weekdays, weekly }

/// 一条 AI 定时任务。
///
/// 存的是「每天第几分钟 + 星期几」，而不是一个绝对时间点：任务要能一直重复，
/// 落盘的东西就不该包含日期。上次执行时间单独记，用来判断这一次跑没跑过。
@immutable
class AiScheduledTask {
  const AiScheduledTask({
    required this.id,
    required this.title,
    required this.prompt,
    required this.minuteOfDay,
    this.cadence = AiScheduleCadence.daily,
    this.weekday = DateTime.monday,
    this.enabled = true,
    this.lastRunAt,
    this.lastResult,
    this.lastOk,
    this.lastFailure,
  });

  /// 错过多久之内还补跑。关掉应用一整天再打开时，昨天的任务不会被翻出来执行。
  static const Duration defaultGrace = Duration(hours: 6);

  static const int maxTitleLength = 40;
  static const int maxPromptLength = 800;

  final String id;
  final String title;

  /// 到点发给模型的那句话。
  final String prompt;

  /// 一天里的第几分钟，0..1439。
  final int minuteOfDay;

  final AiScheduleCadence cadence;

  /// [AiScheduleCadence.weekly] 时的星期几：1 = 周一 … 7 = 周日。
  final int weekday;

  final bool enabled;

  final DateTime? lastRunAt;
  final String? lastResult;

  /// 上一次执行成不成功；从没跑过时为 null。
  final bool? lastOk;

  /// 上一次失败的原因（[AiFailureKind] 的 name），成功时为 null。
  /// 存枚举名而不是文案：界面切语言时提示也跟着变。
  final String? lastFailure;

  int get hour => minuteOfDay ~/ 60;

  int get minute => minuteOfDay % 60;

  /// `08:05`，不含日期。
  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  bool get isValid => title.trim().isNotEmpty && prompt.trim().isNotEmpty;

  /// 这一天要不要跑。
  bool runsOn(DateTime day) => switch (cadence) {
    AiScheduleCadence.daily => true,
    AiScheduleCadence.weekdays =>
      day.weekday >= DateTime.monday && day.weekday <= DateTime.friday,
    AiScheduleCadence.weekly => day.weekday == weekday,
  };

  /// 这一天对应的计划时刻（不判断是否已过）。
  DateTime scheduledOn(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  /// 现在该不该补跑这一次。
  ///
  /// 只在「已经到点、还没跑过、且没超太久」时才返回那个计划时刻。返回它而不是
  /// 布尔值，是为了让 [lastRunAt] 记成计划时间——这样同一分钟的多次轮询不会
  /// 重复触发，也不会因为执行花了几秒钟而错位。
  DateTime? dueAt(DateTime now, {Duration grace = defaultGrace}) {
    if (!enabled) return null;
    // 只看今天和昨天：每周任务跨天时要靠昨天补上。
    for (var offset = 0; offset <= 1; offset++) {
      final day = DateTime(now.year, now.month, now.day - offset);
      if (!runsOn(day)) continue;
      final at = scheduledOn(day);
      if (at.isAfter(now)) continue;
      if (now.difference(at) > grace) continue;
      final last = lastRunAt;
      if (last != null && !last.isBefore(at)) continue;
      return at;
    }
    return null;
  }

  /// 下一次执行时间，永远晚于 [now]。
  DateTime nextRunAfter(DateTime now) {
    for (var offset = 0; offset <= 7; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset);
      if (!runsOn(day)) continue;
      final at = scheduledOn(day);
      if (at.isAfter(now)) return at;
    }
    // 理论上不会走到这里（每周任务最多 7 天内必有一次）。
    return scheduledOn(DateTime(now.year, now.month, now.day + 1));
  }

  AiScheduledTask copyWith({
    String? title,
    String? prompt,
    int? minuteOfDay,
    AiScheduleCadence? cadence,
    int? weekday,
    bool? enabled,
    DateTime? lastRunAt,
    String? lastResult,
    bool? lastOk,
    String? lastFailure,
  }) => AiScheduledTask(
    id: id,
    title: title ?? this.title,
    prompt: prompt ?? this.prompt,
    minuteOfDay: minuteOfDay ?? this.minuteOfDay,
    cadence: cadence ?? this.cadence,
    weekday: weekday ?? this.weekday,
    enabled: enabled ?? this.enabled,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    lastResult: lastResult ?? this.lastResult,
    lastOk: lastOk ?? this.lastOk,
    lastFailure: lastFailure ?? this.lastFailure,
  );

  /// 记一次执行的结果。
  ///
  /// 单独一个方法而不是串 [copyWith]：成功时要真的把上一次的失败原因清成
  /// null，而 `copyWith(lastFailure: null)` 的语义是「不改」。
  AiScheduledTask withRun({
    required DateTime at,
    required bool ok,
    String? result,
    String? failure,
  }) => AiScheduledTask(
    id: id,
    title: title,
    prompt: prompt,
    minuteOfDay: minuteOfDay,
    cadence: cadence,
    weekday: weekday,
    enabled: enabled,
    lastRunAt: at,
    lastResult: ok ? (result ?? '') : null,
    lastOk: ok,
    lastFailure: ok ? null : (failure ?? 'unknown'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'prompt': prompt,
    'minuteOfDay': minuteOfDay,
    'cadence': cadence.name,
    if (cadence == AiScheduleCadence.weekly) 'weekday': weekday,
    'enabled': enabled,
    if (lastRunAt != null) 'lastRunAt': lastRunAt!.toIso8601String(),
    if ((lastResult ?? '').isNotEmpty) 'lastResult': lastResult,
    if (lastOk != null) 'lastOk': lastOk,
    if ((lastFailure ?? '').isNotEmpty) 'lastFailure': lastFailure,
  };

  static AiScheduledTask? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString().trim();
    final prompt = (raw['prompt'] ?? '').toString().trim();
    if (id.isEmpty || title.isEmpty || prompt.isEmpty) return null;
    final minute = (raw['minuteOfDay'] is num)
        ? (raw['minuteOfDay'] as num).toInt()
        : int.tryParse('${raw['minuteOfDay']}') ?? 0;
    final weekday = (raw['weekday'] is num)
        ? (raw['weekday'] as num).toInt()
        : int.tryParse('${raw['weekday']}') ?? DateTime.monday;
    return AiScheduledTask(
      id: id,
      title: title.length > maxTitleLength
          ? title.substring(0, maxTitleLength)
          : title,
      prompt: prompt.length > maxPromptLength
          ? prompt.substring(0, maxPromptLength)
          : prompt,
      minuteOfDay: minute.clamp(0, 1439),
      cadence: AiScheduleCadence.values.firstWhere(
        (value) => value.name == raw['cadence'],
        orElse: () => AiScheduleCadence.daily,
      ),
      weekday: weekday.clamp(DateTime.monday, DateTime.sunday),
      enabled: raw['enabled'] != false,
      lastRunAt: DateTime.tryParse('${raw['lastRunAt'] ?? ''}'),
      lastResult: (raw['lastResult'] ?? '').toString().isEmpty
          ? null
          : raw['lastResult'].toString(),
      lastOk: raw['lastOk'] is bool ? raw['lastOk'] as bool : null,
      lastFailure: (raw['lastFailure'] ?? '').toString().isEmpty
          ? null
          : raw['lastFailure'].toString(),
    );
  }
}
