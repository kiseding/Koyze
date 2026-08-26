import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../../../core/logging/app_log.dart';
import '../../cloud/presentation/cloud_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../custom_source/presentation/custom_source_provider.dart';
import '../../custom_source/domain/custom_source.dart';
import '../domain/sync_phase1_service.dart';
import 'sync_phase1_provider.dart';

enum CloudSyncPhase { idle, syncing, conflict, retryScheduled, error }

final class CloudSyncState {
  const CloudSyncState({
    this.phase = CloudSyncPhase.idle,
    this.message,
    this.conflictId = 0,
    this.report,
  });

  final CloudSyncPhase phase;
  final String? message;
  final int conflictId;
  final SyncReport? report;
}

/// 提取 Dio 错误里的可诊断信息（状态码、路径、服务端错误、request id）。
String _dioDiagnostics(Object error) {
  if (error is! DioException) return error.toString();
  final response = error.response;
  final data = response?.data;
  final serverError = data is Map ? data['error']?.toString() : null;
  final requestId = data is Map
      ? data['requestId']?.toString()
      : response?.headers.value('x-request-id');
  final parts = <String>[
    'HTTP ${response?.statusCode ?? '-'}',
    'path=${error.requestOptions.path}',
    if (serverError != null && serverError.isNotEmpty) 'error=$serverError',
    if (requestId != null && requestId.isNotEmpty) 'requestId=$requestId',
    if (response == null) 'type=${error.type.name}',
  ];
  return parts.join(' ');
}

final cloudSyncProvider =
    StateNotifierProvider<CloudSyncNotifier, CloudSyncState>((ref) {
      final notifier = CloudSyncNotifier(
        phase1: ref.read(syncPhase1ServiceProvider),
        loggedIn: () => ref.read(cloudSessionProvider).loggedIn,
      );
      ref.listen(playlistSyncRevisionProvider, (_, next) {
        if (next.hasValue) notifier.localChanged();
      });
      ref.read(syncPhase1ServiceProvider).onApplyingRemote =
          notifier.onApplyingRemote;
      ref.read(syncPhase1ServiceProvider).onProgress = notifier.onProgress;
      ref.read(syncPhase1ServiceProvider).onLocalEventRecorded =
          notifier.localEventRecorded;
      ref.listen(themeModeProvider, (_, next) {
        notifier.settingChanged('theme_mode', next.index.toString());
      });
      ref.listen(audioQualityProvider, (_, next) {
        notifier.settingChanged('audio_quality', next.index.toString());
      });
      ref.listen(downloadQualityProvider, (_, next) {
        notifier.settingChanged('download_quality', next.index.toString());
      });
      ref.listen(wifiOnlyDownloadProvider, (_, next) {
        notifier.settingChanged('wifi_only_download', next.toString());
      });
      ref.listen(autoResumePlaybackProvider, (_, next) {
        notifier.settingChanged('auto_resume_playback', next.toString());
      });
      ref.listen(defaultSearchPlatformProvider, (_, next) {
        notifier.settingChanged('default_search_platform', next);
      });
      final sourceService = ref.read(customSourceServiceProvider);
      notifier.attachInitialSources(sourceService.sources);
      ref.read(syncPhase1ServiceProvider).attachSources(sourceService);
      ref.listen(customSourceRevisionProvider, (_, __) {
        notifier.sourcesChanged(sourceService.sources);
      });
      ref.read(syncPhase1ServiceProvider).attachSettingApplier((
        key,
        value,
      ) async {
        switch (key) {
          case 'theme_mode':
            await ref
                .read(themeModeProvider.notifier)
                .setThemeMode(
                  ThemeMode.values[(int.tryParse(value) ?? 0).clamp(
                    0,
                    ThemeMode.values.length - 1,
                  )],
                );
          case 'audio_quality':
            await ref
                .read(audioQualityProvider.notifier)
                .setQuality(
                  AudioQualityOption.values[(int.tryParse(value) ?? 1).clamp(
                    0,
                    AudioQualityOption.values.length - 1,
                  )],
                );
          case 'download_quality':
            await ref
                .read(downloadQualityProvider.notifier)
                .setQuality(
                  AudioQualityOption.values[(int.tryParse(value) ?? 1).clamp(
                    0,
                    AudioQualityOption.values.length - 1,
                  )],
                );
          case 'wifi_only_download':
            await ref
                .read(wifiOnlyDownloadProvider.notifier)
                .setWifiOnly(value == 'true');
          case 'auto_resume_playback':
            await ref
                .read(autoResumePlaybackProvider.notifier)
                .setAutoResume(value == 'true');
          case 'default_search_platform':
            await ref
                .read(defaultSearchPlatformProvider.notifier)
                .setPlatform(value);
        }
      });
      ref.listen(cloudSessionProvider, (_, next) {
        notifier.sessionChanged(next.loggedIn);
      }, fireImmediately: true);
      return notifier;
    });

final class CloudSyncNotifier extends StateNotifier<CloudSyncState> {
  CloudSyncNotifier({
    required SyncPhase1Service phase1,
    required bool Function() loggedIn,
  }) : _phase1 = phase1,
       _loggedIn = loggedIn,
       super(const CloudSyncState());

  final SyncPhase1Service _phase1;
  final bool Function() _loggedIn;
  Timer? _debounce;
  Timer? _periodic;
  Timer? _retry;
  Future<void>? _running;
  bool _dirty = false;
  bool _uploadOnlyDirty = false;
  bool _foreground = true;
  bool _applyingRemote = false;
  int _retryIndex = 0;
  int _localGeneration = 0;
  int _conflictGeneration = 0;
  int _sessionGeneration = 0;
  Map<String, CustomSource> _knownSources = const {};
  DateTime? _lastRemoteCheck;

  static const _retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  void onStage(String stage) {
    if (state.phase != CloudSyncPhase.syncing) return;
    AppLog.instance.record('cloud.sync', '阶段：$stage');
    state = CloudSyncState(
      phase: CloudSyncPhase.syncing,
      message: stage,
      conflictId: _conflictGeneration,
    );
  }

  void onApplyingRemote(bool applying) {
    _applyingRemote = applying;
  }

  void onProgress(String message) {
    if (state.phase != CloudSyncPhase.syncing) return;
    state = CloudSyncState(
      phase: CloudSyncPhase.syncing,
      message: message,
      conflictId: _conflictGeneration,
      report: state.report,
    );
  }

  void settingChanged(String key, String value) {
    if (_applyingRemote) return;
    unawaited(_phase1.recordSetting(key, value));
    localChanged();
  }

  void attachInitialSources(List<CustomSource> sources) {
    _knownSources = {for (final source in sources) source.id: source};
  }

  void sourcesChanged(List<CustomSource> sources) {
    final next = {for (final source in sources) source.id: source};
    if (!_applyingRemote) {
      for (final source in next.values) {
        if (_knownSources[source.id]?.updatedAt != source.updatedAt) {
          unawaited(_phase1.recordSource(source));
        }
      }
      for (final id in _knownSources.keys.where(
        (id) => !next.containsKey(id),
      )) {
        unawaited(_phase1.recordSourceRemoval(id));
      }
      localChanged();
    }
    _knownSources = next;
  }

  void sessionChanged(bool loggedIn) {
    final generation = ++_sessionGeneration;
    if (!loggedIn) {
      unawaited(
        _phase1.logout(stillCurrent: () => generation == _sessionGeneration),
      );
      _cancelTimers();
      state = const CloudSyncState();
      return;
    }
    _startPeriodic();
    if (_foreground) unawaited(checkRemote());
  }

  void localChanged() {
    _markLocalChanged(uploadOnly: false);
  }

  void localEventRecorded(Object _) {
    _markLocalChanged(uploadOnly: true);
  }

  void _markLocalChanged({required bool uploadOnly}) {
    if (!_loggedIn() || _applyingRemote) return;
    _uploadOnlyDirty = _dirty ? (_uploadOnlyDirty && uploadOnly) : uploadOnly;
    _dirty = true;
    _localGeneration++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 8), () => unawaited(sync()));
  }

  void resumed() {
    _foreground = true;
    _startPeriodic();
    if (_dirty) {
      unawaited(sync());
    } else if (_lastRemoteCheck == null ||
        DateTime.now().difference(_lastRemoteCheck!) >=
            const Duration(minutes: 5)) {
      unawaited(checkRemote());
    }
  }

  void paused() {
    _foreground = false;
    _debounce?.cancel();
    _debounce = null;
    _retry?.cancel();
    _retry = null;
    _periodic?.cancel();
    _periodic = null;
  }

  Future<void> checkRemote() async {
    if (!_loggedIn() || !_foreground || _running != null) return;
    _lastRemoteCheck = DateTime.now();
    try {
      await sync();
    } catch (error) {
      _scheduleRetry(error);
    }
  }

  Future<void> sync() {
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<void> fullResync() async {
    if (_running != null) return _running!;
    _running = _phase1.fullResync();
    try {
      await _running;
    } finally {
      _running = null;
    }
  }

  Future<void> _run() async {
    if (!_loggedIn() || !_foreground) return;
    _debounce?.cancel();
    final localGeneration = _localGeneration;
    final uploadOnly = _uploadOnlyDirty;
    _uploadOnlyDirty = false;
    AppLog.instance.record('cloud.sync', uploadOnly ? '开始增量事件上传' : '开始事件同步');
    state = CloudSyncState(
      phase: CloudSyncPhase.syncing,
      conflictId: _conflictGeneration,
    );
    try {
      final report = uploadOnly
          ? await _phase1.pushLocalEventsOnly()
          : await _phase1.sync();
      _dirty = _localGeneration != localGeneration;
      _debounce?.cancel();
      _retryIndex = 0;
      _retry?.cancel();
      AppLog.instance.record(
        'cloud.sync',
        '事件同步完成：待同步 ${await _phase1.pendingCount()} 项',
      );
      state = CloudSyncState(conflictId: _conflictGeneration, report: report);
      if (_dirty) localChanged();
    } catch (error) {
      final response = error is DioException ? error.response : null;
      if (response?.statusCode == 409 &&
          response?.data is Map &&
          (response!.data as Map)['error'] == 'revision_conflict') {
        AppLog.instance.record(
          'cloud.sync',
          'revision 冲突（409），自动重试：${_dioDiagnostics(error)}',
          level: AppLogLevel.warning,
        );
        _scheduleRetry(error);
      } else {
        AppLog.instance.record(
          'cloud.sync',
          '同步失败：${_dioDiagnostics(error)}',
          level: AppLogLevel.error,
        );
        _scheduleRetry(error);
      }
    }
  }

  void _scheduleRetry(Object error) {
    final delay = _retryDelays[_retryIndex.clamp(0, _retryDelays.length - 1)];
    if (_retryIndex < _retryDelays.length - 1) _retryIndex++;
    _retry?.cancel();
    _retry = Timer(delay, () {
      if (_foreground) unawaited(sync());
    });
    state = CloudSyncState(
      phase: CloudSyncPhase.retryScheduled,
      message: '同步失败，将在 ${delay.inSeconds} 秒后重试：$error',
      conflictId: state.conflictId,
    );
  }

  void _startPeriodic() {
    if (!_foreground || !_loggedIn() || _periodic != null) return;
    _periodic = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(checkRemote()),
    );
  }

  void _cancelTimers() {
    _debounce?.cancel();
    _periodic?.cancel();
    _retry?.cancel();
    _debounce = null;
    _periodic = null;
    _retry = null;
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }
}
