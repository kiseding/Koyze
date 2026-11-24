import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audio/playback_cache_service.dart';
import '../../../core/network/app_http_client.dart';
import '../../../core/network/music_source_service.dart';
import '../../../core/network/outbound_url.dart';
import '../../../core/network/play_url_result.dart';
import '../../../core/network/source_media_transport.dart';
import '../../../core/storage/portable_mode.dart';
import '../../../core/storage/storage_service.dart';
import '../../player/domain/music_item.dart';
import 'download_task.dart';
import '../../../core/logging/app_log.dart';

enum DownloadNetwork { wifi, mobile, none }

/// 下载目录不可用：没法创建、写不进去，或者根本不是文件系统路径。
///
/// 调用方（设置页）据此提示用户换一个目录，而不是把设置默默改成一条
/// 永远失败的值——下载目录写不进去的话，之后每首歌都会下载失败。
class DownloadDirectoryException implements Exception {
  const DownloadDirectoryException(this.reason, {this.path});

  /// 机器可读的原因：`unsupported_scheme` / `not_writable`。
  final String reason;
  final String? path;

  @override
  String toString() =>
      'DownloadDirectoryException($reason${path == null ? '' : ', path=$path'})';
}

abstract interface class DownloadTaskStorage {
  List<dynamic> load();
  Future<void> save(List<Map<String, dynamic>> tasks);
  List<Map<String, dynamic>> loadQuarantine();
  Future<void> saveQuarantine(List<Map<String, dynamic>> records);

  /// 本服务用过的下载根目录（已解析符号链接）。
  ///
  /// 用户在设置里换过下载目录之后，旧目录里已经下好的文件仍然属于本服务：
  /// 任务记录里的 savePath 要能通过 `isOwnedDownloadPath`，否则重启时会被
  /// 当成「越权路径」隔离掉，下载列表里的历史记录就凭空消失了。
  List<String> loadRoots();

  Future<void> saveRoots(List<String> roots);
}

final class StorageDownloadTaskStorage implements DownloadTaskStorage {
  StorageDownloadTaskStorage(this.storage);
  final StorageService storage;

  static const _tasksKey = 'download_tasks';
  static const _quarantineKey = 'download_tasks_quarantine';
  static const _rootsKey = 'download_roots';

  @override
  List<dynamic> load() {
    final str = storage.getString(_tasksKey);
    if (str == null || str.isEmpty) return const [];
    final decoded = json.decode(str);
    if (decoded is! List) return const [];
    return decoded;
  }

  @override
  Future<void> save(List<Map<String, dynamic>> tasks) async {
    await storage.setJsonList(_tasksKey, tasks);
  }

  @override
  List<Map<String, dynamic>> loadQuarantine() {
    final str = storage.getString(_quarantineKey);
    if (str == null || str.isEmpty) return const [];
    final decoded = json.decode(str);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> saveQuarantine(List<Map<String, dynamic>> records) async {
    await storage.setJsonList(_quarantineKey, records);
  }

  @override
  List<String> loadRoots() {
    try {
      return storage.getStringList(_rootsKey);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveRoots(List<String> roots) async {
    await storage.setStringList(_rootsKey, roots);
  }
}

typedef DownloadExecutor =
    Future<void> Function(
      DownloadTask task,
      CancelToken cancelToken,
      void Function(int received, int total) onProgress,
    );

final class _DownloadAttempt {
  _DownloadAttempt(this.taskId, this.revision, DateTime now)
    : cancelToken = CancelToken(),
      _lastSampleAt = now;

  final String taskId;
  final int revision;
  final CancelToken cancelToken;
  late final Future<void> future;
  int _lastReceived = 0;
  DateTime _lastSampleAt;

  int sampleSpeed(int received, DateTime now) {
    final elapsedMicros = now.difference(_lastSampleAt).inMicroseconds;
    final bytes = received - _lastReceived;
    _lastReceived = received;
    _lastSampleAt = now;
    if (elapsedMicros <= 0 || bytes <= 0) return 0;
    return (bytes * Duration.microsecondsPerSecond / elapsedMicros).round();
  }
}

Future<PlayUrlResult?> downloadWithFreshLinkRetry({
  CancelToken? cancelToken,
  required Future<PlayUrlResult?> Function() resolve,
  required Future<void> Function(PlayUrlResult result) download,
}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    throwIfDownloadCancelled(cancelToken);
    final result = await resolve();
    throwIfDownloadCancelled(cancelToken);
    if (result == null) return null;
    try {
      throwIfDownloadCancelled(cancelToken);
      await download(result);
      throwIfDownloadCancelled(cancelToken);
      return result;
    } on DioException catch (error) {
      throwIfDownloadCancelled(cancelToken);
      final status = error.response?.statusCode;
      final expired =
          status == 401 ||
          status == 403 ||
          status == 404 ||
          status == 410 ||
          status == 416;
      if (!expired || attempt == 1) rethrow;
      throwIfDownloadCancelled(cancelToken);
    } on MediaTransferHttpException catch (error) {
      throwIfDownloadCancelled(cancelToken);
      final expired =
          error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.statusCode == 404 ||
          error.statusCode == 410 ||
          error.statusCode == 416;
      if (!expired || attempt == 1) rethrow;
      throwIfDownloadCancelled(cancelToken);
    }
  }
  return null;
}

void throwIfDownloadCancelled(CancelToken? cancelToken) {
  final error = cancelToken?.cancelError;
  if (error != null) throw error;
}

Future<PlayUrlResult?> resolveFreshPlayableUrl({
  required MusicItem music,
  required String quality,
  required Future<PlayUrlResult?> Function(
    MusicItem music,
    String quality,
    CancelToken? cancelToken,
  )
  resolve,
  CancelToken? cancelToken,
}) async {
  throwIfDownloadCancelled(cancelToken);
  PlayUrlResult? result;
  try {
    result = await resolve(music, quality, cancelToken);
  } catch (_) {
    throwIfDownloadCancelled(cancelToken);
    rethrow;
  }
  throwIfDownloadCancelled(cancelToken);
  return result != null && isPlayableMediaUrl(result.url) ? result : null;
}

DownloadStatus downloadFailureStatus(
  DownloadStatus current, {
  required bool cancelled,
}) {
  if (current == DownloadStatus.paused) return current;
  if (cancelled) return DownloadStatus.paused;
  return DownloadStatus.failed;
}

class DownloadService {
  static const int maximumDownloadBytes = 1024 * 1024 * 1024;
  static const int maximumAggregateBytes = 2 * 1024 * 1024 * 1024;

  final Dio _dio;
  final SourceMediaTransport _sourceMediaTransport;
  PlaybackCacheService? _playbackCache;
  final List<DownloadTask> _tasks = [];
  final StreamController<List<DownloadTask>> _tasksController =
      StreamController<List<DownloadTask>>.broadcast();
  final Map<String, _DownloadAttempt> _attempts = {};
  final Set<String> _activeTaskIds = <String>{};
  Completer<void>? _idleCompleter;
  final int _maxConcurrent;
  bool _wifiOnly;
  final DownloadExecutor? _downloader;
  final String Function() _taskIdFactory;
  final Duration _progressPersistenceInterval;
  final Future<DownloadNetwork> Function() _currentNetwork;
  final DateTime Function() _clock;
  late final StreamSubscription<DownloadNetwork>? _connectivitySubscription;
  Future<void> _persistenceTail = Future<void>.value();
  DateTime _lastProgressPersistence = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastProgressEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _progressEmitInterval = Duration(milliseconds: 150);
  int _connectivityEpoch = 0;

  String? _downloadDir;
  String? _resolvedDownloadRoot;
  final Future<Directory> Function()? _downloadDirectory;

  /// 用户在设置里选的目录。null 表示跟随平台默认目录。
  String? _customDir;

  /// 启动时自定义目录不可用的原因（授权失效等）。
  ///
  /// 非 null 说明 [customDownloadDirectory] 这次没生效、本次运行落回了默认
  /// 目录。设置值本身不改，等授权恢复后下次启动会自动再用它。
  String? _customDirUnavailableReason;

  /// 本服务用过的下载根目录（已解析符号链接，包含当前这个）。
  ///
  /// 换目录之后旧文件仍要能删、能统计、能通过启动时的归属校验，所以这里
  /// 是一个集合而不是单个值，并且会被持久化（见 [DownloadTaskStorage]）。
  final Set<String> _ownedRoots = <String>{};
  MusicSourceService? _musicSourceService;
  DownloadTaskStorage? _storage;
  bool _initialized = false;
  bool _disposed = false;
  bool _tasksDirtyFromReconcile = false;

  static final RegExp _strictDownloadName = RegExp(
    r'^(.+)-([^-]+)-(\d+)\.(part|mp3|m4a|aac|ogg|wav|ape|flac)$',
  );

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;

  /// 下载目录（初始化后可用；未初始化时为 null）。
  String? get downloadDirectory => _downloadDir;

  /// 用户自定义的下载目录；null 表示用的是平台默认目录。
  String? get customDownloadDirectory => _customDir;

  /// 自定义目录本次没能启用时的原因（授权失效、目录被删、只读等）。
  ///
  /// 非 null 时 [downloadDirectory] 指向的是平台默认目录，而
  /// [customDownloadDirectory] 仍是用户当初选的路径——设置页要把这两件事
  /// 都说清楚，否则用户会以为自己的设置被改掉了。
  String? get customDirectoryFallbackReason => _customDirUnavailableReason;

  int get maxCacheSizeMB => 2048;
  Set<String> get activeTaskIds => Set.unmodifiable(_activeTaskIds);

  bool get wifiOnly => _wifiOnly;

  /// 更新「仅 WiFi 下载」策略，不影响下载服务实例本身。
  void setWifiOnly(bool value) {
    if (_wifiOnly == value) return;
    _wifiOnly = value;
    if (value) {
      _connectivityEpoch++;
      _processQueue();
    } else {
      _processQueue();
    }
  }

  Future<void> get idle {
    if (_activeTaskIds.isEmpty) return Future<void>.value();
    return (_idleCompleter ??= Completer<void>()).future;
  }

  Future<void> get persistenceIdle => _persistenceTail;

  DownloadService({
    Dio? dio,
    int maxConcurrent = 3,
    bool wifiOnly = false,
    Stream<DownloadNetwork>? connectivity,
    Future<DownloadNetwork> Function()? currentNetwork,
    String Function()? taskIdFactory,
    DownloadExecutor? downloader,
    DownloadTaskStorage? storage,
    Future<Directory> Function()? downloadDirectory,
    String? customDownloadDirectory,
    Duration progressPersistenceInterval = const Duration(seconds: 2),
    DateTime Function()? clock,
    SourceMediaTransport? sourceMediaTransport,
  }) : assert(maxConcurrent > 0),
       _dio = dio ?? AppHttpClient.createDownload(),
       _sourceMediaTransport = sourceMediaTransport ?? SourceMediaTransport(),
       _maxConcurrent = maxConcurrent,
       _wifiOnly = wifiOnly,
       _downloader = downloader,
       _storage = storage,
       _downloadDirectory = downloadDirectory,
       _customDir = switch (customDownloadDirectory?.trim()) {
         final value? when value.isNotEmpty => value,
         _ => null,
       },
       _taskIdFactory = taskIdFactory ?? const Uuid().v4,
       _currentNetwork = currentNetwork ?? _platformNetwork,
       _clock = clock ?? DateTime.now,
       _progressPersistenceInterval = progressPersistenceInterval {
    _connectivitySubscription = connectivity?.listen(_onNetworkChanged);
  }

  static Future<DownloadNetwork> _platformNetwork() async {
    final result = await Connectivity().checkConnectivity();
    return _networkFrom(result);
  }

  static DownloadNetwork _networkFrom(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return DownloadNetwork.wifi;
    }
    if (results.contains(ConnectivityResult.none)) return DownloadNetwork.none;
    return DownloadNetwork.mobile;
  }

  void setMusicSourceService(MusicSourceService service) {
    _musicSourceService = service;
  }

  void setPlaybackCache(PlaybackCacheService cache) {
    _playbackCache = cache;
  }

  Future<void> init() async {
    if (_initialized) return;
    _storage ??= StorageDownloadTaskStorage(await StorageService.instance);
    // 必须早于任务加载：历史任务里的 savePath 可能落在换目录之前的旧根
    // 目录里，归属校验没有这些根就会把它们全判成越权并隔离掉。
    _ownedRoots.addAll(
      _storage!.loadRoots().map((root) => root.trim()).where((r) => r.isNotEmpty),
    );
    await _initDownloadDir();
    await _loadFromStorageIndependently();
    await _reconcileDownloadDirectory();
    await _persistReconciledSnapshotIfChanged();
    _initialized = true;
    _processQueue();
  }

  Future<void> _loadFromStorageIndependently() async {
    final saved = _storage!.load();
    final quarantine = List<Map<String, dynamic>>.from(
      _storage!.loadQuarantine(),
    );
    final valid = <DownloadTask>[];
    var tasksChanged = false;

    for (final raw in saved) {
      try {
        final task = DownloadTask.decodePersisted(raw);
        if (task.savePath != null &&
            task.savePath!.isNotEmpty &&
            !isOwnedDownloadPath(task.savePath!)) {
          quarantine.add(
            _quarantineEntry(
              raw is Map ? Map<String, dynamic>.from(raw) : raw,
              FormatException(
                'savePath outside download root: ${task.savePath}',
              ),
            ),
          );
          tasksChanged = true;
          continue;
        }
        valid.add(task);
      } catch (error) {
        quarantine.add(
          _quarantineEntry(
            raw is Map ? Map<String, dynamic>.from(raw) : raw,
            error,
          ),
        );
        tasksChanged = true;
      }
    }

    _tasks
      ..clear()
      ..addAll(valid);
    _emitTasks();

    if (tasksChanged ||
        quarantine.length != _storage!.loadQuarantine().length) {
      await _storage!.saveQuarantine(quarantine);
      await _saveToStorage();
    }
  }

  Map<String, dynamic> _quarantineEntry(Object? raw, Object error) {
    return {
      'record': raw,
      'reason': error.toString(),
      'quarantinedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> _reconcileDownloadDirectory() async {
    final dirPath = _downloadDir;
    if (dirPath == null) return;
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    final files = <File>[];
    // 列举失败不能冒泡到 init()：启动时这个目录可能刚好不可访问（iOS /
    // 鸿蒙的授权还没恢复、外接卷还没挂上）。对账只是「把磁盘上的实际文件和
    // 任务列表对齐」这种尽力而为的维护动作，读不到就当这次没对账，绝不能
    // 因此让应用起不来。
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) files.add(entity);
      }
    } catch (error, stackTrace) {
      AppLog.instance.record(
        'download.reconcile',
        'listing download directory failed, skipping reconcile: '
        '$dirPath ($error)',
        level: AppLogLevel.warning,
        stackTrace: stackTrace,
      );
      return;
    }

    final matchedFinals = <String, List<File>>{};

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final match = _strictDownloadName.firstMatch(name);
      if (match == null) continue;
      if (!isOwnedDownloadPath(file.path)) continue;

      final base = match.group(1)!;
      final tail = match.group(2)!;
      final revision = int.parse(match.group(3)!);
      final kind = match.group(4)!;

      if (kind == 'part') continue;

      DownloadTask? owner;
      for (final task in _tasks) {
        if (task.attemptRevision == revision &&
            (task.id.endsWith(tail) || safeDownloadBaseName(task.id) == base)) {
          owner = task;
          break;
        }
      }
      if (owner != null) {
        matchedFinals.putIfAbsent(owner.id, () => []).add(file);
      }
    }

    final quarantine = List<Map<String, dynamic>>.from(
      _storage!.loadQuarantine(),
    );
    var quarantineChanged = false;

    for (final entry in matchedFinals.entries) {
      final taskId = entry.key;
      final candidates = entry.value;
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index < 0) continue;
      final task = _tasks[index];
      final recoverable =
          task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.pending;

      if (!recoverable) continue;

      if (candidates.length > 1) {
        quarantine.add(
          _quarantineEntry(
            task.toJson(),
            FormatException(
              'multiple final files for ${task.id}@${task.attemptRevision}',
            ),
          ),
        );
        quarantineChanged = true;
        _tasks.removeAt(index);
        _tasksDirtyFromReconcile = true;
        continue;
      }

      final nonEmpty = <File>[];
      for (final f in candidates) {
        if (await f.length() > 0) nonEmpty.add(f);
      }

      if (nonEmpty.length == 1) {
        final recovered = nonEmpty.single;
        final length = await recovered.length();
        _tasks[index] = task.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          savePath: recovered.path,
          fileSize: length,
          completedAt: DateTime.now().toUtc(),
          clearErrorMsg: true,
        );
        _tasksDirtyFromReconcile = true;
      }
    }

    for (var i = _tasks.length - 1; i >= 0; i--) {
      final task = _tasks[i];
      if (task.status != DownloadStatus.completed) continue;
      final path = task.savePath;
      final file = path == null ? null : File(path);
      if (file == null || !await file.exists() || await file.length() == 0) {
        // Reconcile stale task metadata, but never infer file ownership from
        // a task record strongly enough to delete the path during startup.
        _tasks.removeAt(i);
        _tasksDirtyFromReconcile = true;
      }
    }

    for (var i = 0; i < _tasks.length; i++) {
      final t = _tasks[i];
      if (t.status == DownloadStatus.downloading) {
        _tasks[i] = t.copyWith(
          status: DownloadStatus.pending,
          progress: 0.0,
          clearSavePath: true,
          clearErrorMsg: true,
        );
        _tasksDirtyFromReconcile = true;
      }
    }

    if (quarantineChanged) {
      await _storage!.saveQuarantine(quarantine);
    }
    if (_tasksDirtyFromReconcile) {
      _emitTasks();
    }
  }

  Future<void> _persistReconciledSnapshotIfChanged() async {
    if (!_tasksDirtyFromReconcile) return;
    await _saveToStorage();
    _tasksDirtyFromReconcile = false;
  }

  Future<void> _saveToStorage() async {
    _storage ??= StorageDownloadTaskStorage(await StorageService.instance);
    final data = _tasks.map((t) => t.toJson()).toList(growable: false);
    final write = _persistenceTail
        .catchError((_) {})
        .then((_) => _storage!.save(data));
    _persistenceTail = write.catchError((_) {});
    return write;
  }

  /// 建立下载目录。自定义目录不可访问时**降级到默认目录**，绝不抛异常。
  ///
  /// 这一层必须兜住，否则整个应用起不来。iOS / 鸿蒙的目录选择器给的是受
  /// 授权保护的路径（iOS 是 security-scoped bookmark，鸿蒙是原生 URI）：授权
  /// 在用户选定那一刻是活的，写探针也能过，但**重启后**要靠
  /// `SecurityScopedDirectory.restore()` 重新激活。书签失效、被系统回收、
  /// 用户在「文件」App 里把目录删了，恢复就会失败，于是这里的
  /// `create()` / `list()` 抛 `PathAccessException`。
  ///
  /// 5.2.0 上线「下载目录设置」后真实踩到：用户把下载目录指到 iOS「文件」
  /// App 的 Music 文件夹，重启后卡在启动页——
  /// `PathAccessException: Directory listing failed, path =
  /// '.../AppGroup/[uuid]/File Provider Storage/Music/'`。
  ///
  /// 降级策略：保留用户的设置值（不要偷偷改掉他的选择，下次授权恢复还能
  /// 用），只让**本次运行**回落到默认目录，并把降级原因记进 AppLog 与
  /// [downloadDirectoryFallbackReason]，设置页据此提示。
  Future<void> _initDownloadDir() async {
    final custom = _customDir?.trim();
    if (custom != null && custom.isNotEmpty) {
      try {
        final dir = Directory(custom);
        await dir.create(recursive: true);
        final resolved = await dir.resolveSymbolicLinks();
        _downloadDir = dir.path;
        _resolvedDownloadRoot = resolved;
        _ownedRoots.add(resolved);
        return;
      } catch (error) {
        _customDirUnavailableReason = error.toString();
        AppLog.instance.record(
          'download.directory',
          'custom download directory unavailable, falling back to default: '
          '$custom ($error)',
          level: AppLogLevel.warning,
        );
      }
    }
    final dir = await _defaultDirectory();
    await dir.create(recursive: true);
    _downloadDir = dir.path;
    _resolvedDownloadRoot = await dir.resolveSymbolicLinks();
    _ownedRoots.add(_resolvedDownloadRoot!);
    // 桌面端换过默认落点：旧目录里的文件仍属于本服务，别把它们隔离掉。
    await _adoptLegacyDefaultDirectory();
  }

  /// 把桌面旧默认目录登记为归属根。
  ///
  /// 只在没有自定义目录、且旧目录存在时才做。用户显式选了目录的话，旧默认
  /// 目录里的文件本来就不该由这次运行接管（他可能已经把目录指到别处）。
  Future<void> _adoptLegacyDefaultDirectory() async {
    final custom = _customDir?.trim();
    if (custom != null && custom.isNotEmpty) return;
    try {
      final legacy = await _legacyDefaultDirectory();
      if (legacy == null) return;
      final resolved = await legacy.resolveSymbolicLinks();
      if (_resolvedDownloadRoot == resolved) return;
      if (!_ownedRoots.add(resolved)) return;
      await _persistOwnedRoots();
    } catch (error) {
      AppLog.instance.record(
        'download.directory',
        'adopting legacy default directory failed: $error',
        level: AppLogLevel.warning,
      );
    }
  }

  /// 公共「下载」文件夹里属于本应用的子目录名。
  ///
  /// 四个平台的终点都是它：桌面直接落进去，移动端把副本导出进去。用户在
  /// 文件管理器里打开「下载」就能看到一个 Koyze 文件夹，而不是一堆散落的
  /// 音频和封面。
  static const publicDownloadsFolderName = 'Koyze';

  /// 能不能把公共「下载」目录当成长期写入的下载根。
  ///
  /// 只有桌面可以。移动端（Android / iOS / 鸿蒙）的公共下载目录要么写不
  /// 进去（iOS 沙盒、鸿蒙手机），要么需要额外的存储权限模型（Android），
  /// 所以那边的下载根仍是应用私有目录，「看得见」靠一次导出完成。
  static bool get _supportsDirectPublicDownloads =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 平台默认下载目录。
  ///
  /// 桌面落在系统「下载」文件夹下的 `Koyze` 子目录：用户在文件管理器里点
  /// 「下载」就能看到，和其他应用一致。便携模式（Windows 下 exe 旁的
  /// `portable.flag`）例外，仍落在可执行文件同级的 `portable_data/downloads`，
  /// 这样整个应用连同数据可以一起搬走。
  ///
  /// 移动端落在应用文档目录下的 `downloads`，设置页的「下载目录」里可以
  /// 把它们导出到系统「下载/Koyze」。
  static Future<Directory> defaultDownloadDirectory() async {
    final portableRoot = PortableMode.root;
    if (portableRoot != null) {
      return Directory('$portableRoot${Platform.pathSeparator}downloads');
    }
    if (_supportsDirectPublicDownloads) {
      final downloads = await getDownloadsDirectory();
      // Linux 上 `getDownloadsDirectory()` 依赖 xdg-user-dirs，没配的话
      // 返回 null，退到应用文档目录而不是让下载直接失败。
      if (downloads != null) {
        return Directory(
          '${downloads.path}${Platform.pathSeparator}$publicDownloadsFolderName',
        );
      }
    }
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}${Platform.pathSeparator}downloads');
  }

  /// 默认目录：构造函数可以注入一个（测试、便携模式），否则走平台默认。
  Future<Directory> _defaultDirectory() async {
    final factory = _downloadDirectory;
    return factory != null ? factory() : defaultDownloadDirectory();
  }

  /// 桌面端早期版本的默认下载目录（应用文档下的 `downloads`）。
  ///
  /// 5.2.4 把桌面的默认落点从那里挪到了公共「下载/Koyze」，老用户的下载
  /// 记录里全是旧路径。不把旧目录认定为归属根的话，升级后第一次启动就会
  /// 把它们全判成越权路径隔离掉——下载列表凭空清空是最容易被当成「丢数据」
  /// 的一类 bug。只在桌面返回，且只在它确实存在时才加进归属集合。
  Future<Directory?> _legacyDefaultDirectory() async {
    if (kIsWeb || !_supportsDirectPublicDownloads) return null;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}downloads');
    return await dir.exists() ? dir : null;
  }

  /// 切换下载目录，立刻生效。
  ///
  /// [path] 为 null / 空串表示恢复默认目录。切换前会建目录并写入一个探针
  /// 文件：用户选的可能是只读位置、系统不存在的卷，或者（Android / iOS）
  /// 只有 SAF 授权的 `content://` 树——直接 Dart IO 写不进去。校验失败会抛
  /// [DownloadDirectoryException]，当前目录保持不变，调用方据此提示。
  ///
  /// 已下载的文件不会被搬走（跨卷复制可能几个 G，失败还会丢数据）。旧目录
  /// 会进入归属集合并且持久化，因此历史任务仍然可播放、可删除、可统计。
  Future<String> switchDownloadDirectory(String? path) async {
    final trimmed = path?.trim();
    final reset = trimmed == null || trimmed.isEmpty;
    if (!reset && _looksLikeNonFileSystemPath(trimmed)) {
      throw DownloadDirectoryException('unsupported_scheme', path: trimmed);
    }

    final target = reset ? await _defaultDirectory() : Directory(trimmed);
    try {
      await target.create(recursive: true);
      final probe = File(
        '${target.path}${Platform.pathSeparator}.koyze-write-probe',
      );
      await probe.writeAsString('koyze', flush: true);
      await probe.delete();
    } on Object catch (_) {
      throw DownloadDirectoryException('not_writable', path: target.path);
    }

    final resolved = await target.resolveSymbolicLinks();
    final previous = _resolvedDownloadRoot;
    if (previous != null && previous != resolved) {
      _ownedRoots.add(previous);
      await _persistOwnedRoots();
    }
    _customDir = reset ? null : target.path;
    _downloadDir = target.path;
    _resolvedDownloadRoot = resolved;
    _ownedRoots.add(resolved);
    return _downloadDir!;
  }

  /// `content://`、`file://docs/...` 这类地址不是文件系统路径，`dart:io`
  /// 打不开。抛出去让用户换一个位置，比把它存进设置、之后每首歌都失败好。
  static bool _looksLikeNonFileSystemPath(String path) {
    if (!path.contains('://')) return false;
    final uri = Uri.tryParse(path);
    return uri == null || uri.scheme != 'file' || uri.host.isNotEmpty;
  }

  Future<void> _persistOwnedRoots() async {
    final storage = _storage;
    if (storage == null) return;
    final roots = _ownedRoots.toList()..sort();
    try {
      await storage.saveRoots(roots);
    } catch (error) {
      AppLog.instance.record(
        'download.directory',
        'persisting owned roots failed: $error',
        level: AppLogLevel.warning,
      );
    }
  }

  bool isOwnedDownloadPath(String path) {
    final candidate = _resolveOwnershipCandidate(path);
    if (candidate == null) return false;
    final current = _resolvedDownloadRoot;
    if (current != null && _isInsideRoot(candidate, current)) return true;
    for (final root in _ownedRoots) {
      if (_isInsideRoot(candidate, root)) return true;
    }
    return false;
  }

  static bool _isInsideRoot(String candidate, String root) {
    if (root.isEmpty) return false;
    return candidate == root ||
        candidate.startsWith('$root${Platform.pathSeparator}');
  }

  String? _resolveOwnershipCandidate(String path) {
    try {
      final absolute = File(path).absolute.path;
      final entity = FileSystemEntity.typeSync(absolute, followLinks: false);
      if (entity != FileSystemEntityType.notFound) {
        return File(absolute).resolveSymbolicLinksSync();
      }

      var current = Directory(absolute).parent;
      final missing = <String>[File(absolute).uri.pathSegments.last];
      while (true) {
        if (current.existsSync()) {
          final resolvedAncestor = current.resolveSymbolicLinksSync();
          final suffix = missing.reversed.join(Platform.pathSeparator);
          return '$resolvedAncestor${Platform.pathSeparator}$suffix';
        }
        final parent = current.parent;
        if (parent.path == current.path) {
          return absolute;
        }
        missing.add(
          current.uri.pathSegments.isEmpty
              ? current.path
              : current.uri.pathSegments.last,
        );
        current = parent;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> addTask(MusicItem music, {String? quality}) async {
    if (_tasks.any(
      (t) =>
          t.musicIdentityKey == music.identityKey &&
          t.status != DownloadStatus.failed,
    )) {
      return;
    }

    if (_downloader == null && _downloadDir == null) {
      await _initDownloadDir();
    }

    final task = DownloadTask(
      id: _taskIdFactory(),
      musicId: music.id,
      name: music.name,
      singer: music.singer,
      createdAt: DateTime.now(),
      quality: quality,
      platform: music.platform,
      source: music.source,
      songmid: music.songmid,
      hash: music.hash,
      album: music.album,
      artwork: music.artwork,
      duration: music.duration.inSeconds,
      status: DownloadStatus.pending,
    );

    _tasks.add(task);
    _emitTasks();
    await _saveToStorage();
    _processQueue();
  }

  Future<void> addTasks(List<MusicItem> songs, {String? quality}) async {
    for (final song in songs) {
      await addTask(song, quality: quality);
    }
  }

  Future<void> _runAttempt(DownloadTask task, _DownloadAttempt attempt) async {
    final latest = _taskById(task.id);
    if (!_isCurrent(attempt) || latest == null) return;

    if (_downloader == null && _downloadDir == null) {
      await _initDownloadDir();
    }

    final cancelToken = attempt.cancelToken;
    _updateCurrent(attempt, status: DownloadStatus.downloading, errorMsg: '');

    final partPath = _partPathFor(task.id, attempt.revision);

    try {
      if (_downloader != null) {
        await _downloader(latest, cancelToken, (received, total) {
          _updateTransferProgress(attempt, received, total);
        });
        if (_isCurrent(attempt) && !cancelToken.isCancelled) {
          _updateCurrent(
            attempt,
            status: DownloadStatus.completed,
            progress: 1.0,
          );
        }
        return;
      }
      final music = _musicFromTask(latest);
      // 丢弃任务里缓存的 CDN 直链：签名会过期，重试时复用会 403。
      // 每次下载/重试都向源重新解析（与播放路径一致）。
      final preferred = (latest.quality == null || latest.quality!.isEmpty)
          ? '320k'
          : latest.quality!;
      final cachedPath = await _playbackCache?.copyCachedToDirectory(
        platform: latest.platform ?? latest.source ?? 'kw',
        songId: latest.songmid?.isNotEmpty == true
            ? latest.songmid!
            : (latest.hash?.isNotEmpty == true ? latest.hash! : latest.musicId),
        quality: preferred,
        destinationDirectory: _downloadDir!,
      );
      if (cachedPath != null) {
        final cachedFile = File(cachedPath);
        final extension = cachedPath.substring(cachedPath.lastIndexOf('.'));
        final savePath = _finalPathFor(task.id, attempt.revision, extension);
        final size = await cachedFile.length();
        await cachedFile.copy(savePath);
        await _safeDelete(cachedPath);
        if (_isCurrent(attempt)) {
          _updateCurrent(
            attempt,
            status: DownloadStatus.completed,
            progress: 1.0,
            savePath: savePath,
            completedAt: DateTime.now(),
            fileSize: size,
            quality: preferred,
            errorMsg: '',
          );
        }
        return;
      }
      var completedOk = false;
      final resolved = await downloadWithFreshLinkRetry(
        cancelToken: cancelToken,
        resolve: () =>
            _resolveFreshUrl(music, preferred, cancelToken: cancelToken),
        download: (resolved) async {
          final downloadUrl = normalizeMediaUrl(resolved.url);
          _updateCurrent(
            attempt,
            quality: resolved.actualQuality,
            progress: 0.0,
          );
          debugPrint(
            '[DownloadService] fetch q=${resolved.actualQuality} '
            'host=${Uri.tryParse(downloadUrl)?.host}',
          );

          try {
            final existingBytes = await _downloadDirectoryBytes();
            final remaining = maximumAggregateBytes - existingBytes;
            if (remaining <= 0) {
              throw const MediaTransferLimitException(maximumAggregateBytes);
            }
            final ceiling = remaining < maximumDownloadBytes
                ? remaining
                : maximumDownloadBytes;
            if (resolved.fromCustomSource) {
              await _sourceMediaTransport.download(
                downloadUrl,
                partPath,
                headers: _downloadHeaders(
                  downloadUrl,
                  resolved.platform,
                  extra: resolved.headers,
                ),
                cancelToken: cancelToken,
                byteLimit: ceiling,
              );
            } else {
              await _downloadBoundedWithDio(
                downloadUrl,
                partPath,
                resolved.platform,
                cancelToken,
                ceiling,
                attempt,
                headers: resolved.headers,
              );
            }
          } on DioException catch (e) {
            await _safeDeleteOwned(partPath, attempt);
            if (CancelToken.isCancel(e)) rethrow;
            debugPrint(
              '[DownloadService] HTTP fail q=${resolved.actualQuality} '
              'code=${e.response?.statusCode}',
            );
            rethrow;
          }
        },
      );

      if (resolved != null) {
        final downloadUrl = normalizeMediaUrl(resolved.url);
        final after = _taskById(task.id);
        if (!_isCurrent(attempt) ||
            after == null ||
            after.status != DownloadStatus.downloading) {
          await _safeDeleteOwned(partPath, attempt);
          return;
        }

        final part = File(partPath);
        if (!await part.exists() || await part.length() == 0) {
          await _safeDeleteOwned(partPath, attempt);
        } else if (await part.length() < 2048) {
          await _safeDeleteOwned(partPath, attempt);
        } else {
          final header = await part
              .openRead(0, 64)
              .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
          if (_looksLikeNonAudio(header)) {
            await _safeDeleteOwned(partPath, attempt);
          } else {
            final urlExt = _guessExt(downloadUrl);
            final qualityExt = _qualityExt(resolved.actualQuality);
            final detectedExt = PlaybackCacheService.extensionFromBytes(
              header,
              fallback: urlExt == '.audio' ? qualityExt : urlExt,
            );
            if (detectedExt == '.audio') {
              await _safeDeleteOwned(partPath, attempt);
            } else {
              final savePath = _finalPathFor(
                task.id,
                attempt.revision,
                detectedExt,
              );
              final out = File(savePath);
              if (!_isCurrent(attempt)) {
                await _safeDeleteOwned(partPath, attempt);
                return;
              }
              if (await out.exists()) {
                if (!_isCurrent(attempt)) return;
                await _safeDeleteOwned(savePath, attempt);
              }
              if (!_isCurrent(attempt) ||
                  !await _promotePartFile(part, savePath, attempt)) {
                await _safeDeleteOwned(savePath, attempt);
                return;
              }
              final size = await File(savePath).length();
              if (size > maximumDownloadBytes ||
                  await _downloadDirectoryBytes() > maximumAggregateBytes) {
                await _safeDeleteOwned(savePath, attempt);
                throw const MediaTransferLimitException(maximumDownloadBytes);
              }
              if (!_isCurrent(attempt)) {
                await _safeDeleteOwned(savePath, attempt);
                return;
              }
              _updateCurrent(
                attempt,
                status: DownloadStatus.completed,
                progress: 1.0,
                savePath: savePath,
                completedAt: DateTime.now(),
                fileSize: size,
                errorMsg: '',
              );
              completedOk = true;
            }
          }
        }
      }

      if (!completedOk &&
          _isCurrent(attempt) &&
          _taskById(task.id)?.status != DownloadStatus.paused &&
          !cancelToken.isCancelled) {
        _updateCurrent(
          attempt,
          status: DownloadStatus.failed,
          errorMsg: '无法获取下载链接',
        );
      }
    } on DioException catch (e) {
      await _safeDeleteOwned(partPath, attempt);
      if (CancelToken.isCancel(e)) {
        final cur = _taskById(task.id);
        if (_isCurrent(attempt) &&
            cur != null &&
            cur.status == DownloadStatus.downloading) {
          _updateCurrent(attempt, status: DownloadStatus.paused);
        }
        return;
      }
      _updateCurrent(
        attempt,
        status: DownloadStatus.failed,
        errorMsg: _dioErrorMessage(e),
      );
    } catch (e) {
      await _safeDeleteOwned(partPath, attempt);
      final current = _taskById(task.id)?.status;
      if (_isCurrent(attempt) && current != null) {
        final status = downloadFailureStatus(
          current,
          cancelled: cancelToken.isCancelled,
        );
        _updateCurrent(
          attempt,
          status: status,
          errorMsg: status == DownloadStatus.failed ? e.toString() : '',
        );
      }
    } finally {
      if (identical(_attempts[task.id], attempt)) {
        _attempts.remove(task.id);
        _activeTaskIds.remove(task.id);
        if (_activeTaskIds.isEmpty && _idleCompleter != null) {
          _idleCompleter!.complete();
          _idleCompleter = null;
        }
      }
      if (!_disposed) _processQueue();
    }
  }

  /// 始终向音源重新解析；不使用任务/MusicItem 上过期的 CDN 直链。
  Future<PlayUrlResult?> _resolveFreshUrl(
    MusicItem music,
    String quality, {
    CancelToken? cancelToken,
  }) async {
    if (_musicSourceService == null) return null;
    throwIfDownloadCancelled(cancelToken);
    // 仅 file:// 本地路径可直用
    final existing = music.url;
    if (existing != null &&
        (existing.startsWith('file:') || existing.startsWith('/'))) {
      return PlayUrlResult(
        url: existing,
        requestedQuality: quality,
        actualQuality: quality,
        platform: music.platform,
      );
    }
    try {
      // 不带 url，强制源重新签发 CDN 地址
      final clean = MusicItem(
        id: music.id,
        name: music.name,
        singer: music.singer,
        album: music.album,
        duration: music.duration,
        source: music.source,
        platform: music.platform,
        artwork: music.artwork,
        songmid: music.songmid,
        hash: music.hash,
        meta: music.meta,
      );
      return await resolveFreshPlayableUrl(
        music: clean,
        quality: quality,
        cancelToken: cancelToken,
        resolve: (music, quality, token) => _musicSourceService!
            .resolvePlayableUrl(
              music,
              preferredQuality: quality,
              cancelToken: token,
            )
            .timeout(const Duration(seconds: 25)),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      debugPrint(
        '[DownloadService] resolve q=$quality failed '
        'type=${e.type.name} status=${e.response?.statusCode}',
      );
    } catch (e) {
      debugPrint(
        '[DownloadService] resolve q=$quality failed type=${e.runtimeType}',
      );
    }
    return null;
  }

  Map<String, String> _downloadHeaders(
    String url,
    String platform, {
    Map<String, String>? extra,
  }) {
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      'Referer': _refererFor(url, platform),
      'Accept': '*/*',
      // 部分 CDN 对无 Range 的整文件 GET 更友好；明确不要条件缓存
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    };
    // 自建服务器的鉴权头（Plex 的 X-Plex-Token、WebDAV 的 Basic）由解析
    // 播放地址时一并给出，不带上就只会拿到 401。
    if (extra != null) {
      for (final entry in extra.entries) {
        headers.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return headers;
  }

  Future<void> _downloadBoundedWithDio(
    String url,
    String destination,
    String platform,
    CancelToken token,
    int ceiling,
    _DownloadAttempt attempt, {
    Map<String, String>? headers,
  }) async {
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: token,
      options: Options(
        headers: _downloadHeaders(url, platform, extra: headers),
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    final body = response.data;
    if (body == null) throw const MediaTransferHttpException(0);
    final declared = int.tryParse(
      response.headers.value('content-length') ?? '',
    );
    if (declared != null && declared > ceiling) {
      throw MediaTransferLimitException(ceiling);
    }
    RandomAccessFile? output;
    try {
      output = await File(destination).open(mode: FileMode.write);
      var received = 0;
      await for (final chunk in body.stream) {
        throwIfDownloadCancelled(token);
        if (chunk.length > ceiling - received) {
          throw MediaTransferLimitException(ceiling);
        }
        received += chunk.length;
        await output.writeFrom(chunk);
        _updateTransferProgress(attempt, received, declared ?? -1);
      }
      await output.flush();
    } finally {
      await output?.close();
    }
  }

  MusicItem _musicFromTask(DownloadTask task) {
    // 故意不带 task.url：CDN 签名链极易过期，下载一律重新解析
    return MusicItem(
      id: task.musicId,
      name: task.name,
      singer: task.singer,
      album: task.album ?? '',
      duration: Duration(seconds: task.duration ?? 0),
      source: task.source ?? '',
      platform: task.platform ?? 'kw',
      artwork: task.artwork,
      songmid: task.songmid,
      hash: task.hash,
    );
  }

  void _processQueue() {
    if (_disposed) return;
    final slots = _maxConcurrent - _activeTaskIds.length;
    if (slots <= 0) return;
    if (_wifiOnly) {
      final epoch = _connectivityEpoch;
      _currentNetwork().then((network) {
        if (!_disposed &&
            _wifiOnly &&
            epoch == _connectivityEpoch &&
            network == DownloadNetwork.wifi) {
          _processQueueAllowed();
        }
      });
      return;
    }
    _processQueueAllowed();
  }

  void _processQueueAllowed() {
    if (_disposed) return;
    final slots = _maxConcurrent - _activeTaskIds.length;
    if (slots <= 0) return;
    final pendingTasks = _tasks
        .where((t) => t.status == DownloadStatus.pending)
        .take(slots)
        .toList();
    for (final task in pendingTasks) {
      if (!_activeTaskIds.add(task.id)) continue;
      final revision = task.attemptRevision + 1;
      _updateTask(task.id, attemptRevision: revision);
      final attempt = _DownloadAttempt(task.id, revision, _clock());
      _attempts[task.id] = attempt;
      attempt.future = _runAttempt(_taskById(task.id)!, attempt);
      unawaited(attempt.future);
    }
  }

  void _onNetworkChanged(DownloadNetwork network) {
    if (!_wifiOnly) return;
    if (network == DownloadNetwork.wifi) {
      _processQueue();
      return;
    }
    _connectivityEpoch++;
    for (final attempt in _attempts.values.toList()) {
      _invalidate(attempt, status: DownloadStatus.pending, progress: 0.0);
      attempt.cancelToken.cancel('wifi policy');
    }
  }

  void pauseTask(String taskId) {
    final attempt = _attempts[taskId];
    if (attempt != null) {
      _invalidate(attempt, status: DownloadStatus.paused);
      attempt.cancelToken.cancel('paused');
      return;
    }
    _updateTask(taskId, status: DownloadStatus.paused);
  }

  void resumeTask(String taskId) {
    final task = _taskById(taskId);
    if (task == null) return;
    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed) {
      _updateTask(
        taskId,
        status: DownloadStatus.pending,
        progress: 0.0,
        errorMsg: '',
      );
      _processQueue();
    }
  }

  String _partPathFor(String taskId, int revision) {
    final task = _taskById(taskId);
    return '$_downloadDir/${completedPathName(taskId, revision, '', songName: task?.name)}.part';
  }

  String _finalPathFor(String taskId, int revision, String extension) {
    final task = _taskById(taskId);
    return '$_downloadDir/${completedPathName(taskId, revision, extension, songName: task?.name)}';
  }

  void cancelTask(String taskId) {
    final attempt = _attempts[taskId];
    if (attempt != null) {
      _invalidate(attempt);
      attempt.cancelToken.cancel('cancelled');
    }
    final task = _taskById(taskId);
    if (task != null) {
      if (task.savePath != null) {
        unawaited(_safeDelete(task.savePath!));
      }
    }
    _tasks.removeWhere((t) => t.id == taskId);
    _emitTasks();
    unawaited(_saveToStorage());
  }

  void retryTask(String taskId) {
    final task = _taskById(taskId);
    if (task == null) return;
    final attempt = _attempts[taskId];
    if (attempt != null) {
      _invalidate(attempt);
      attempt.cancelToken.cancel('retry');
    }
    _updateTask(
      taskId,
      status: DownloadStatus.pending,
      progress: 0.0,
      errorMsg: '',
      savePath: '',
    );
    _processQueue();
  }

  Future<void> deleteDownloaded(String taskId) async {
    final task = _taskById(taskId);
    if (task == null) return;
    if (task.savePath != null) {
      await _safeDelete(task.savePath!);
    }
    final attempt = _attempts[taskId];
    if (attempt != null) {
      _invalidate(attempt);
      attempt.cancelToken.cancel('deleted');
    }
    _tasks.removeWhere((t) => t.id == taskId);
    _emitTasks();
    await _saveToStorage();
  }

  DownloadTask? _taskById(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index < 0) return null;
    return _tasks[index];
  }

  void _updateTask(
    String taskId, {
    DownloadStatus? status,
    double? progress,
    int? speed,
    String? errorMsg,
    String? savePath,
    bool clearSavePath = false,
    bool clearErrorMsg = false,
    DateTime? completedAt,
    int? fileSize,
    String? url,
    String? quality,
    int? attemptRevision,
    bool persistProgress = false,
  }) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index < 0) return;

    final task = _tasks[index];
    final resetSpeed =
        status == DownloadStatus.completed ||
        status == DownloadStatus.failed ||
        status == DownloadStatus.paused ||
        status == DownloadStatus.pending;
    _tasks[index] = task.copyWith(
      status: status,
      progress: progress,
      speed: resetSpeed ? 0 : speed,
      errorMsg: errorMsg,
      clearErrorMsg: clearErrorMsg || errorMsg == '',
      savePath: savePath,
      clearSavePath: clearSavePath || savePath == '',
      completedAt: completedAt,
      fileSize: fileSize,
      url: url,
      quality: quality,
      attemptRevision: attemptRevision,
    );
    // 进度流节流：下载中每 chunk 都 emit 会让下载页以极高频率重建。
    // 状态/结果类变化（terminal 或非进度更新）立即 emit。
    final now = _clock();
    final terminalNow =
        status == DownloadStatus.completed ||
        status == DownloadStatus.failed ||
        status == DownloadStatus.paused ||
        status == DownloadStatus.pending;
    final isProgressOnly = persistProgress && !terminalNow;
    if (!isProgressOnly ||
        now.difference(_lastProgressEmitAt) >= _progressEmitInterval) {
      if (isProgressOnly) _lastProgressEmitAt = now;
      _emitTasks();
    }
    final terminal =
        status == DownloadStatus.completed ||
        status == DownloadStatus.failed ||
        status == DownloadStatus.paused;
    if (!persistProgress ||
        terminal ||
        now.difference(_lastProgressPersistence) >=
            _progressPersistenceInterval) {
      if (persistProgress) _lastProgressPersistence = now;
      unawaited(_saveToStorage());
    }
  }

  void _updateTransferProgress(
    _DownloadAttempt attempt,
    int received,
    int total,
  ) {
    if (received < 0) return;
    _updateCurrent(
      attempt,
      progress: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
      speed: attempt.sampleSpeed(received, _clock()),
      persistProgress: true,
    );
  }

  bool _isCurrent(_DownloadAttempt attempt) {
    return !_disposed &&
        identical(_attempts[attempt.taskId], attempt) &&
        _taskById(attempt.taskId)?.attemptRevision == attempt.revision;
  }

  void _updateCurrent(
    _DownloadAttempt attempt, {
    DownloadStatus? status,
    double? progress,
    int? speed,
    String? errorMsg,
    String? savePath,
    bool clearSavePath = false,
    bool clearErrorMsg = false,
    DateTime? completedAt,
    int? fileSize,
    String? url,
    String? quality,
    bool persistProgress = false,
  }) {
    if (!_isCurrent(attempt)) return;
    _updateTask(
      attempt.taskId,
      status: status,
      progress: progress,
      speed: speed,
      errorMsg: errorMsg,
      savePath: savePath,
      clearSavePath: clearSavePath,
      clearErrorMsg: clearErrorMsg,
      completedAt: completedAt,
      fileSize: fileSize,
      url: url,
      quality: quality,
      persistProgress: persistProgress,
    );
  }

  void _invalidate(
    _DownloadAttempt attempt, {
    DownloadStatus? status,
    double? progress,
  }) {
    final task = _taskById(attempt.taskId);
    if (task == null || task.attemptRevision != attempt.revision) return;
    _updateTask(
      attempt.taskId,
      attemptRevision: attempt.revision + 1,
      status: status,
      progress: progress,
    );
  }

  void _emitTasks() {
    if (!_disposed && !_tasksController.isClosed) _tasksController.add(_tasks);
  }

  Future<List<DownloadTask>> getDownloadedTasks() async {
    return _tasks.where((t) => t.status == DownloadStatus.completed).toList();
  }

  bool isDownloaded(MusicItem music) {
    return _tasks.any(
      (t) =>
          t.musicIdentityKey == music.identityKey &&
          t.status == DownloadStatus.completed,
    );
  }

  String? getDownloadPath(MusicItem music) {
    try {
      final task = _tasks.firstWhere(
        (t) =>
            t.musicIdentityKey == music.identityKey &&
            t.status == DownloadStatus.completed,
      );
      final path = task.savePath;
      if (path == null || !isOwnedDownloadPath(path)) return null;
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<int> getCacheSize() async {
    int totalSize = 0;
    for (final task in _tasks) {
      final path = task.savePath;
      if (path == null || !isOwnedDownloadPath(path)) continue;
      final file = File(path);
      if (await file.exists()) {
        totalSize += await file.length();
      }
    }
    return totalSize;
  }

  Future<int> _downloadDirectoryBytes() async {
    final path = _downloadDir;
    if (path == null) return 0;
    var total = 0;
    // 同 _reconcileDownloadDirectory：这里的失败只影响「缓存占用」这个展示
    // 数字，不值得让调用方（设置页刷新、清理逻辑）整条链断掉。
    try {
      await for (final entity in Directory(path).list(followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
    } catch (error) {
      AppLog.instance.record(
        'download.directory',
        'measuring download directory failed: $path ($error)',
        level: AppLogLevel.warning,
      );
    }
    return total;
  }

  Future<void> clearCache() async {
    for (final task in _tasks) {
      if (task.savePath != null) {
        await _safeDelete(task.savePath!);
      }
      final attempt = _attempts[task.id];
      if (attempt != null) {
        _invalidate(attempt);
        attempt.cancelToken.cancel('cleared');
      }
    }
    _tasks.clear();
    _emitTasks();
    await _saveToStorage();
  }

  Future<void> clearCacheWithLRU({required int maxBytes}) async {
    final completedTasks =
        _tasks.where((t) => t.status == DownloadStatus.completed).toList()
          ..sort(
            (a, b) => (a.completedAt ?? a.createdAt).compareTo(
              b.completedAt ?? b.createdAt,
            ),
          );

    int currentSize = await getCacheSize();

    for (final task in completedTasks) {
      if (currentSize <= maxBytes) break;
      final path = task.savePath;
      if (path == null || !isOwnedDownloadPath(path)) continue;
      final file = File(path);
      if (await file.exists()) {
        final fileSize = await file.length();
        await _safeDelete(path);
        currentSize -= fileSize;
        _tasks.remove(task);
      }
    }
    _emitTasks();
    await _saveToStorage();
  }

  String _refererFor(String url, String platform) {
    final p = platform.toLowerCase();
    if (p == 'tx' || url.contains('qq.com') || url.contains('gtimg')) {
      return 'https://y.qq.com/';
    }
    if (p == 'wy' || url.contains('163.com') || url.contains('music.126')) {
      return 'https://music.163.com/';
    }
    if (p == 'kw' || url.contains('kuwo')) {
      return 'https://www.kuwo.cn/';
    }
    if (p == 'kg' || url.contains('kugou')) {
      return 'https://www.kugou.com/';
    }
    return 'https://www.google.com/';
  }

  bool _looksLikeNonAudio(List<int> header) {
    if (header.isEmpty) return true;
    final start = String.fromCharCodes(
      header.take(32),
    ).trimLeft().toLowerCase();
    if (start.startsWith('<!doctype') ||
        start.startsWith('<html') ||
        start.startsWith('<?xml') ||
        start.startsWith('{') ||
        start.startsWith('[') ||
        start.startsWith('error')) {
      return true;
    }
    return false;
  }

  String _guessExt(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    for (final ext in [
      '.flac',
      '.m4a',
      '.mp3',
      '.aac',
      '.ogg',
      '.wav',
      '.ape',
    ]) {
      if (path.contains(ext)) return ext;
    }
    return '.audio';
  }

  String _qualityExt(String quality) {
    final q = quality.toLowerCase();
    if (q == 'flac' || q == 'flac24bit' || q == 'hires') return '.flac';
    if (q == 'aac') return '.aac';
    if (q == 'm4a') return '.m4a';
    return '.mp3';
  }

  String _dioErrorMessage(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '下载超时';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '网络连接失败';
    }
    final code = e.response?.statusCode;
    if (code != null) return 'HTTP $code';
    final msg = e.message;
    if (msg != null && msg.isNotEmpty) return msg;
    return '下载失败';
  }

  Future<void> _safeDelete(String path) async {
    try {
      if (!isOwnedDownloadPath(path)) return;
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (error) {
      AppLog.instance.record('download.cleanup', 'deleting file $path failed: $error', level: AppLogLevel.warning);
    }
  }

  Future<void> _safeDeleteOwned(String path, _DownloadAttempt attempt) async {
    if (!isOwnedDownloadPath(path) || !_isAttemptOwnedPath(path, attempt)) {
      return;
    }
    await _safeDelete(path);
  }

  bool _isAttemptOwnedPath(String path, _DownloadAttempt attempt) {
    final prefix =
        '${safeDownloadBaseName(attempt.taskId)}-${attempt.revision}';
    final name = File(path).uri.pathSegments.last;
    return name == '$prefix.part' ||
        (name.startsWith('$prefix.') && !name.endsWith('.part'));
  }

  /// Promotes only while the owning attempt remains current.
  Future<bool> _promotePartFile(
    File part,
    String savePath,
    _DownloadAttempt attempt,
  ) async {
    if (!_isCurrent(attempt)) return false;
    try {
      await part.rename(savePath);
      return _isCurrent(attempt);
    } on PathNotFoundException catch (e) {
      debugPrint('[DownloadService] rename missing: $e');
    } catch (e) {
      debugPrint('[DownloadService] rename failed, try copy: $e');
    }
    if (!_isCurrent(attempt) || !await part.exists()) {
      if (!_isCurrent(attempt)) return false;
      throw PathNotFoundException(part.path, const OSError(), '临时文件不存在');
    }
    if (!_isCurrent(attempt)) return false;
    await part.copy(savePath);
    if (!_isCurrent(attempt)) return false;
    await _safeDeleteOwned(part.path, attempt);
    return _isCurrent(attempt);
  }

  /// 文件名安全化：去掉路径分隔与异常字符。
  static String safeDownloadBaseName(String musicId) {
    final cleaned = musicId
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^\.|\.$'), '');
    if (cleaned.isEmpty) return 'track';
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  static String completedPathName(
    String taskId,
    int attemptRevision,
    String extension, {
    String? songName,
  }) {
    // 文件名以歌曲名为基础（可读），尾部保留 taskId 短标识与版本号，
    // 既保证下载目录里一眼可辨，又让 reconcile 能按短标识恢复任务归属。
    final shortId = taskId.length > 8
        ? taskId.substring(taskId.length - 8)
        : taskId;
    final base = safeDownloadBaseName(
      songName?.trim().isNotEmpty == true ? songName! : 'track',
    );
    return '$base-$shortId-$attemptRevision$extension';
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_idleCompleter != null && !_idleCompleter!.isCompleted) {
      _idleCompleter!.complete();
      _idleCompleter = null;
    }
    final attempts = _attempts.values.toList();
    for (final attempt in attempts) {
      _invalidate(attempt);
      attempt.cancelToken.cancel('disposed');
    }
    await _connectivitySubscription?.cancel();
    await Future.wait(attempts.map((attempt) => attempt.future));
    await _saveToStorage().catchError((_) {});
    await _persistenceTail;
    _dio.close();
    await _tasksController.close();
  }
}
