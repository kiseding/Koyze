// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';
import '../../../core/storage/storage_service.dart';
import '../domain/ai_config.dart';
import '../domain/ai_schedule.dart';
import '../domain/ai_schedule_store.dart';
import 'ai_provider.dart';

final aiScheduleStoreProvider = Provider<AiScheduleStore>(
  (ref) => AiScheduleStore(),
);

/// 定时任务列表。增删改都在这里，落盘由 [AiScheduleStore] 负责。
final aiSchedulesProvider =
    NotifierProvider<AiSchedulesNotifier, List<AiScheduledTask>>(
      AiSchedulesNotifier.new,
    );

class AiSchedulesNotifier extends BuildlessNotifier<List<AiScheduledTask>> {
  AiSchedulesNotifier({StorageLoader? storage})
    : _store = AiScheduleStore(storage: storage),
      super(const <AiScheduledTask>[]) {
    unawaited(_hydrate());
  }

  final AiScheduleStore _store;
  bool _touched = false;

  Future<void> _hydrate() async {
    final tasks = await _store.load();
    if (!mounted || _touched) return;
    publish(tasks);
  }

  static String newId() =>
      'task_${DateTime.now().microsecondsSinceEpoch.toString()}';

  Future<void> add(AiScheduledTask task) =>
      _save([...value, task]);

  Future<void> update(AiScheduledTask task) => _save([
    for (final item in value) item.id == task.id ? task : item,
  ]);

  Future<void> remove(String id) =>
      _save([for (final item in value) if (item.id != id) item]);

  Future<void> setEnabled(String id, bool enabled) => _save([
    for (final item in value)
      if (item.id == id) item.copyWith(enabled: enabled) else item,
  ]);

  /// 记一次执行结果。成功时清掉上一次的失败原因，反之亦然。
  Future<void> recordRun(
    String id, {
    required DateTime at,
    String? result,
    String? failure,
    required bool ok,
  }) => _save([
    for (final item in value)
      if (item.id == id)
        item.withRun(at: at, result: result, failure: failure, ok: ok)
      else
        item,
  ]);

  Future<void> _save(List<AiScheduledTask> tasks) async {
    _touched = true;
    publish(tasks);
    await _store.save(tasks);
  }
}

/// 一次执行的结果，给界面显示「跑完了/失败了」用。
class AiScheduleRunResult {
  const AiScheduleRunResult({
    required this.ok,
    this.text = '',
    this.failure,
    this.skipped = false,
  });

  final bool ok;
  final String text;

  /// 失败原因（[AiFailureKind]），成功时为 null。
  final AiFailureKind? failure;

  /// 上一次还在跑，这次没执行。
  final bool skipped;
}

/// 到点检查。
///
/// 只在有启用中的任务时才开轮询——没有任务时不留下任何定时器。每 30 秒看一次
/// 「有没有哪个任务的计划时刻已经过去但还没执行」，有就串行跑一个（不并发，
/// 免得同时开几个模型请求）。应用被杀掉期间错过的，只要在 6 小时内就补一次。
final aiScheduleRunnerProvider = Provider<AiScheduleRunner>((ref) {
  final runner = AiScheduleRunner(ref);
  ref.onDispose(runner.dispose);
  ref.listen<List<AiScheduledTask>>(
    aiSchedulesProvider,
    (_, next) => runner.sync(hasWork: next.any((task) => task.enabled)),
    fireImmediately: true,
  );
  return runner;
});

class AiScheduleRunner {
  AiScheduleRunner(this._ref);

  static const Duration pollInterval = Duration(seconds: 30);

  final Ref _ref;
  Timer? _timer;
  bool _ticking = false;

  /// 正在执行的任务 id，界面据此转圈、同时避免重复触发。
  final Set<String> _running = {};

  bool isRunning(String id) => _running.contains(id);

  /// 按「有没有活要干」开关轮询。
  void sync({required bool hasWork}) {
    if (!hasWork) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(tick()));
    // 刚打开应用时先补一次，别等第一个 30 秒。
    unawaited(tick());
  }

  Future<void> tick({DateTime? now}) async {
    if (_ticking) return;
    _ticking = true;
    try {
      final clock = now ?? DateTime.now();
      for (final task in _ref.read(aiSchedulesProvider)) {
        if (!task.enabled || _running.contains(task.id)) continue;
        final due = task.dueAt(clock);
        if (due == null) continue;
        await _execute(task, at: due);
        // 一轮只跑一个：多个任务同时到点时排队，下一轮 30 秒后再来。
        break;
      }
    } finally {
      _ticking = false;
    }
  }

  /// 用户点「立即执行」。
  Future<AiScheduleRunResult> runNow(AiScheduledTask task) async {
    if (_running.contains(task.id)) {
      return const AiScheduleRunResult(ok: false, skipped: true);
    }
    return _execute(task, at: DateTime.now());
  }

  Future<AiScheduleRunResult> _execute(
    AiScheduledTask task, {
    required DateTime at,
  }) async {
    _running.add(task.id);
    try {
      final config = _ref.read(aiConfigProvider);
      if (!config.isConfigured) {
        return _fail(task, at, AiFailureKind.notConfigured);
      }
      final key = await _ref.read(aiConfigProvider.notifier).loadKey();
      if (key == null || key.isEmpty) {
        return _fail(task, at, AiFailureKind.unauthorized);
      }
      final reply = await _ref
          .read(aiAgentProvider)
          .run(
            config: config,
            apiKey: key,
            history: [AiMessage(AiRole.user, task.prompt)],
            toolbox: _ref.read(aiToolboxProvider),
            useTools: config.toolsEnabled,
            timeout: const Duration(minutes: 3),
          );
      await _ref
          .read(aiSchedulesProvider.notifier)
          .recordRun(task.id, at: at, result: reply.text, ok: true);
      _ref
          .read(aiChatProvider.notifier)
          .recordScheduled(
            title: task.title,
            text: reply.text,
            toolRuns: reply.toolRuns,
          );
      return AiScheduleRunResult(ok: true, text: reply.text);
    } on AiException catch (error) {
      return _fail(task, at, error.kind, error.detail);
    } catch (_) {
      return _fail(task, at, AiFailureKind.network);
    } finally {
      _running.remove(task.id);
    }
  }

  Future<AiScheduleRunResult> _fail(
    AiScheduledTask task,
    DateTime at,
    AiFailureKind kind, [
    String? detail,
  ]) async {
    await _ref
        .read(aiSchedulesProvider.notifier)
        .recordRun(task.id, at: at, failure: kind.name, ok: false);
    _ref
        .read(aiChatProvider.notifier)
        .recordScheduled(
          title: task.title,
          failure: kind,
          detail: (detail ?? '').trim().isEmpty ? null : detail!.trim(),
        );
    return AiScheduleRunResult(ok: false, failure: kind);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _running.clear();
  }
}
