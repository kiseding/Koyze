// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';
import '../../custom_source/domain/custom_source.dart';
import '../../custom_source/presentation/custom_source_provider.dart';
import '../data/source_check_store.dart';
import '../domain/source_check_policy.dart';
import '../domain/source_check_report.dart';
import '../domain/source_check_runner.dart';

final sourceCheckStoreProvider = Provider<SourceCheckStore>(
  (ref) => SourceCheckStore(),
);

/// 选源策略单例：检测跑完写进来，播放时读出去。
///
/// 挂在 provider 上而不是页面里，是因为播放链路在用户还没打开检测页时就要用到它，
/// 所以这里主动把上次的结果读回来一次。
final sourceCheckPolicyProvider = Provider<SourceCheckPolicy>((ref) {
  final policy = SourceCheckPolicy();
  final store = ref.watch(sourceCheckStoreProvider);
  unawaited(
    store.load().then((book) {
      if (book.isNotEmpty) policy.update(book);
    }),
  );
  return policy;
});

final sourceCheckRunnerProvider = Provider<SourceCheckRunner>((ref) {
  return SourceCheckRunner(service: ref.watch(customSourceServiceProvider));
});

@immutable
class SourceCheckState {
  const SourceCheckState({
    this.book = SourceCheckBook.empty,
    this.loaded = false,
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.current = '',
    this.activeSourceId = '',
    this.cancelled = false,
  });

  final SourceCheckBook book;
  final bool loaded;
  final bool running;
  final int done;
  final int total;
  final String current;
  final String activeSourceId;
  final bool cancelled;

  double get fraction => total <= 0 ? 0 : done / total;

  SourceCheckState copyWith({
    SourceCheckBook? book,
    bool? loaded,
    bool? running,
    int? done,
    int? total,
    String? current,
    String? activeSourceId,
    bool? cancelled,
  }) {
    return SourceCheckState(
      book: book ?? this.book,
      loaded: loaded ?? this.loaded,
      running: running ?? this.running,
      done: done ?? this.done,
      total: total ?? this.total,
      current: current ?? this.current,
      activeSourceId: activeSourceId ?? this.activeSourceId,
      cancelled: cancelled ?? this.cancelled,
    );
  }
}

final sourceCheckControllerProvider =
    NotifierProvider<SourceCheckController, SourceCheckState>(
      SourceCheckController.new,
    );

/// 跑检测并把结论落盘、喂给 [SourceCheckPolicy]。
class SourceCheckController extends BuildlessNotifier<SourceCheckState> {
  SourceCheckController() : super(const SourceCheckState());

  bool _cancelRequested = false;

  @override
  SourceCheckState build() {
    unawaited(_hydrate());
    return super.build();
  }

  Future<void> _hydrate() async {
    final store = ref.read(sourceCheckStoreProvider);
    final book = await store.load();
    if (!mounted) return;
    ref.read(sourceCheckPolicyProvider).update(book);
    publish(value.copyWith(book: book, loaded: true));
  }

  void cancel() {
    _cancelRequested = true;
  }

  Future<void> runAll(List<CustomSource> sources) async {
    if (value.running || sources.isEmpty) return;
    _cancelRequested = false;
    publish(
      value.copyWith(
        running: true,
        done: 0,
        total: 0,
        current: '',
        activeSourceId: '',
        cancelled: false,
      ),
    );

    final runner = ref.read(sourceCheckRunnerProvider);
    final reports = await runner.runAll(
      sources,
      isCancelled: () => _cancelRequested,
      onProgress: _onProgress,
    );
    if (!mounted) return;

    var next = value.book;
    for (final report in reports) {
      next = next.withReport(report);
    }
    next = next.retainOnly(sources.map((source) => source.id));
    final store = ref.read(sourceCheckStoreProvider);
    await store.save(next);
    if (!mounted) return;
    ref.read(sourceCheckPolicyProvider).update(next);
    publish(
      value.copyWith(
        book: next,
        running: false,
        cancelled: _cancelRequested,
        current: '',
        activeSourceId: '',
      ),
    );
  }

  /// 只测一个脚本：音源卡片上那一栏「音源检测」用的就是这条路。
  ///
  /// 和 [runAll] 共用同一份状态，所以两个入口不会同时跑——已经在测别的脚本时
  /// 直接忽略这次请求，免得两个检测抢同一个引擎。
  Future<void> runSource(CustomSource source) async {
    if (value.running) return;
    _cancelRequested = false;
    publish(
      value.copyWith(
        running: true,
        done: 0,
        total: 0,
        current: '',
        activeSourceId: source.id,
        cancelled: false,
      ),
    );

    final runner = ref.read(sourceCheckRunnerProvider);
    SourceCheckReport? report;
    try {
      report = await runner.runScript(
        source,
        isCancelled: () => _cancelRequested,
        onProgress: _onProgress,
      );
    } catch (_) {
      // 单个脚本跑挂不该把整页状态留在「检测中」。
      report = null;
    }
    if (!mounted) return;

    var book = value.book;
    if (report != null) {
      book = book.withReport(report);
      await ref.read(sourceCheckStoreProvider).save(book);
      if (!mounted) return;
      ref.read(sourceCheckPolicyProvider).update(book);
    }
    publish(
      value.copyWith(
        book: book,
        running: false,
        cancelled: _cancelRequested,
        current: '',
        activeSourceId: '',
      ),
    );
  }

  void _onProgress(SourceCheckProgress progress) {
    if (!mounted) return;
    var book = value.book;
    for (final report in progress.reports.values) {
      book = book.withReport(report);
    }
    publish(
      value.copyWith(
        book: book,
        done: progress.done,
        total: progress.total,
        current: progress.current,
        activeSourceId: progress.currentSourceId,
      ),
    );
  }
}
