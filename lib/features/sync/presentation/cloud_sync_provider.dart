import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/state/buildless_notifier.dart';
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

final cloudSyncProvider = NotifierProvider<CloudSyncNotifier, CloudSyncState>(
  CloudSyncNotifier.new,
);

final class CloudSyncNotifier extends BuildlessNotifier<CloudSyncState> {
  CloudSyncNotifier({SyncPhase1Service? phase1, bool Function()? loggedIn})
    : _phase1Override = phase1,
      _loggedInOverride = loggedIn,
      _phase1 = phase1,
      _loggedIn = loggedIn ?? (() => false),
      super(const CloudSyncState());

  final SyncPhase1Service? _phase1Override;
  final bool Function()? _loggedInOverride;
  SyncPhase1Service? _phase1;
  bool Function() _loggedIn;
  bool _wired = false;

  SyncPhase1Service get _service {
    final service = _phase1;
    if (service == null) {
      throw StateError('CloudSyncNotifier used before build()');
    }
    return service;
  }

  @override
  CloudSyncState build() {
    _phase1 = _phase1Override ?? ref.read(syncPhase1ServiceProvider);
    _loggedIn =
        _loggedInOverride ?? () => ref.read(cloudSessionProvider).loggedIn;
    if (_wired) return super.build();
    _wired = true;

    ref.listen(playlistSyncRevisionProvider, (_, next) {
      if (next.hasValue) localChanged();
    });
    ref.read(syncPhase1ServiceProvider).onApplyingRemote = onApplyingRemote;
    ref.read(syncPhase1ServiceProvider).onProgress = onProgress;
    ref.read(syncPhase1ServiceProvider).onLocalEventRecorded =
        localEventRecorded;
    ref.listen(audioQualityProvider, (_, next) {
      settingChanged('audio_quality', next.index.toString());
    });
    ref.listen(downloadQualityProvider, (_, next) {
      settingChanged('download_quality', next.index.toString());
    });
    ref.listen(wifiOnlyDownloadProvider, (_, next) {
      settingChanged('wifi_only_download', next.toString());
    });
    ref.listen(autoResumePlaybackProvider, (_, next) {
      settingChanged('auto_resume_playback', next.toString());
    });
    ref.listen(defaultSearchPlatformProvider, (_, next) {
      settingChanged('default_search_platform', next);
    });
    final sourceService = ref.read(customSourceServiceProvider);
    ref.read(syncPhase1ServiceProvider).attachSources(sourceService);
    // init() is async. Attaching the still-empty in-memory list here would
    // mark hydration complete, so the later disk load looks like brand-new
    // sources and re-queues every custom source on each launch.
    unawaited(
      sourceService.init().then((_) {
        if (!mounted) return;
        attachInitialSources(sourceService.sources);
      }),
    );
    ref.listen(customSourceRevisionProvider, (_, __) {
      sourcesChanged(sourceService.sources);
    });
    ref.read(syncPhase1ServiceProvider).attachSettingApplier((
      key,
      value,
    ) async {
      switch (key) {
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
      // Initial CloudSessionState is loaded:false/loggedIn:false. Treating
      // that as logout wipes synced identity before the restored token lands.
      if (!next.loaded) return;
      sessionChanged(next.loggedIn);
    }, fireImmediately: true);

    return super.build();
  }

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
  final int _conflictGeneration = 0;
  int _sessionGeneration = 0;
  bool _sourcesReady = false;
  Map<String, CustomSource> _knownSources = const {};
  DateTime? _lastRemoteCheck;

  static const _retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  void onStage(String stage) {
    if (value.phase != CloudSyncPhase.syncing) return;
    AppLog.instance.record('cloud.sync', '阶段：$stage');
    publish(
      CloudSyncState(
        phase: CloudSyncPhase.syncing,
        message: stage,
        conflictId: _conflictGeneration,
      ),
    );
  }

  void onApplyingRemote(bool applying) {
    _applyingRemote = applying;
    if (!applying) {
      _knownSources = {
        for (final source in _service.sources) source.id: source,
      };
    }
  }

  void onProgress(String message) {
    if (value.phase != CloudSyncPhase.syncing) return;
    publish(
      CloudSyncState(
        phase: CloudSyncPhase.syncing,
        message: message,
        conflictId: _conflictGeneration,
        report: value.report,
      ),
    );
  }

  static const _localOnlySettings = {'theme_mode'};

  void settingChanged(String key, String value) {
    if (_applyingRemote || _localOnlySettings.contains(key)) return;
    unawaited(_service.recordSetting(key, value));
    localChanged();
  }

  void attachInitialSources(List<CustomSource> sources) {
    _knownSources = {for (final source in sources) source.id: source};
    _sourcesReady = true;
  }

  void sourcesChanged(List<CustomSource> sources) {
    final next = {for (final source in sources) source.id: source};
    if (!_sourcesReady) {
      _knownSources = next;
      _sourcesReady = true;
      return;
    }
    if (_applyingRemote) {
      _knownSources = next;
      return;
    }
    var changed = false;
    for (final source in next.values) {
      final known = _knownSources[source.id];
      if (known == null || !known.sameSyncDefinition(source)) {
        unawaited(_service.recordSource(source));
        changed = true;
      }
    }
    for (final id in _knownSources.keys.where((id) => !next.containsKey(id))) {
      unawaited(_service.recordSourceRemoval(id));
      changed = true;
    }
    _knownSources = next;
    if (changed) localChanged();
  }

  void sessionChanged(bool loggedIn, {bool loaded = true}) {
    if (!loaded) return;
    final generation = ++_sessionGeneration;
    if (!loggedIn) {
      unawaited(
        _service.logout(stillCurrent: () => generation == _sessionGeneration),
      );
      _cancelTimers();
      publish(const CloudSyncState());
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
    // 保留 debounce、重试和周期任务：同步由应用根部托管，离开页面或进入
    // 后台后仍可继续；系统若挂起进程，恢复时 resumed() 会再次补偿检查。
  }

  Future<void> checkRemote() async {
    if (!_loggedIn() || _running != null) return;
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
    _running = _service.fullResync();
    try {
      await _running;
    } finally {
      _running = null;
    }
  }

  Future<void> _run() async {
    if (!_loggedIn()) return;
    _debounce?.cancel();
    final localGeneration = _localGeneration;
    final uploadOnly = _uploadOnlyDirty;
    _uploadOnlyDirty = false;
    AppLog.instance.record('cloud.sync', uploadOnly ? '开始增量事件上传' : '开始事件同步');
    publish(
      CloudSyncState(
        phase: CloudSyncPhase.syncing,
        conflictId: _conflictGeneration,
      ),
    );
    try {
      final report = uploadOnly
          ? await _service.pushLocalEventsOnly()
          : await _service.sync();
      _dirty = _localGeneration != localGeneration;
      _debounce?.cancel();
      _retryIndex = 0;
      _retry?.cancel();
      AppLog.instance.record(
        'cloud.sync',
        '事件同步完成：待同步 ${await _service.pendingCount()} 项',
      );
      publish(CloudSyncState(conflictId: _conflictGeneration, report: report));
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
    _retry = Timer(delay, () => unawaited(sync()));
    publish(
      CloudSyncState(
        phase: CloudSyncPhase.retryScheduled,
        message: '同步失败，将在 ${delay.inSeconds} 秒后重试：$error',
        conflictId: value.conflictId,
      ),
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
  void onTeardown() {
    _cancelTimers();
  }
}
