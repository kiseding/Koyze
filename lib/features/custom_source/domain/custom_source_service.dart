import 'dart:async';
import 'dart:convert';

import '../../../core/network/ios_source_transport.dart';
import '../../../core/network/source_request_policy.dart';
import '../../../core/storage/storage_service.dart';
import '../domain/custom_source.dart';
import '../domain/custom_source_engine.dart';
import '../domain/source_script_safety.dart' as script_safety;
import '../domain/source_script_validation.dart';
import '../../player/domain/music_item.dart';

class CustomSourceService {
  CustomSourceService({
    SourceRequestSandbox? importSandbox,
    StorageService? storage,
    StorageLoader? storageLoader,
    DateTime Function()? clock,
  }) : _storage = storage,
       _storageLoader = storageLoader,
       _clock = clock ?? DateTime.now,
       _importSandbox =
           importSandbox ??
           SourceRequestSandbox(
             policy: SourceRequestPolicy(
               maximumResponseBytes: maximumScriptBytes,
             ),
             transport: IOSSourceTransport(
               maximumResponseBytes: maximumScriptBytes,
             ).call,
             maximumRedirects: 5,
             maximumInFlightBytes: maximumScriptBytes,
             maximumConcurrentResponseBodies: 1,
             maximumConcurrentRequests: 1,
           );

  static const String _storageKey = 'custom_sources';
  static const String _quarantineKey = 'custom_sources_quarantine';
  static const int maximumScriptBytes = 2 * 1024 * 1024;
  static const Duration importTimeout = Duration(seconds: 15);

  final List<CustomSource> _sources = [];
  final Map<String, CustomSourceEngine> _engines = {};
  final StreamController<int> _revisionController =
      StreamController<int>.broadcast();
  final SourceRequestSandbox _importSandbox;
  final StorageLoader? _storageLoader;
  final DateTime Function() _clock;
  StorageService? _storage;
  bool _initialized = false;
  Future<void>? _initFuture;
  Future<void> _mutationTail = Future<void>.value();

  List<CustomSource> get sources => List.unmodifiable(_sources);
  List<CustomSource> get enabledSources =>
      _sources.where((s) => s.isEnabled).toList();
  Stream<int> get revisionStream => _revisionController.stream;
  int _revision = 0;

  Future<void> init() {
    if (_initialized) return Future.value();
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    try {
      _storage ??= await (_storageLoader ?? () => StorageService.instance)();
      await _loadSources();
      _initialized = true;
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
  }

  bool _exceedsScriptByteLimit(String text) =>
      utf8.encode(text).length > maximumScriptBytes;

  Future<void> _loadSources() async {
    final jsonStr = _storage?.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return;

    final quarantine = _loadQuarantine();
    dynamic decoded;
    try {
      decoded = json.decode(jsonStr);
    } catch (error) {
      quarantine.add(_quarantineEntry(jsonStr, error));
      await _persistRecoveredSources(const [], quarantine);
      return;
    }
    if (decoded is! List) {
      quarantine.add(
        _quarantineEntry(decoded, const FormatException('root is not a list')),
      );
      await _persistRecoveredSources(const [], quarantine);
      return;
    }

    final loaded = <CustomSource>[];
    var sanitized = false;
    for (final record in decoded) {
      try {
        if (record is! Map) throw const FormatException('record is not a map');
        var source = CustomSource.fromJson(Map<String, dynamic>.from(record));
        if (source.id.trim().isEmpty ||
            source.name.trim().isEmpty ||
            source.script.trim().isEmpty) {
          throw const FormatException('required source field is empty');
        }
        if (source.isEnabled &&
            script_safety.hasUnsafeSynchronousLoop(source.script)) {
          source = source.copyWith(isEnabled: false);
          sanitized = true;
        }
        loaded.add(source);
      } catch (error) {
        quarantine.add(_quarantineEntry(record, error));
        sanitized = true;
      }
    }
    _publish(_dedupeSources(loaded));
    if (sanitized || _sources.length != decoded.length) {
      await _persistRecoveredSources(_sources, quarantine);
    }
  }

  Future<void> _persistRecoveredSources(
    List<CustomSource> sources,
    List<Map<String, dynamic>> quarantine,
  ) async {
    try {
      await _storage!.setString(_quarantineKey, json.encode(quarantine));
    } catch (_) {}
    try {
      await _saveSources(sources);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _loadQuarantine() {
    final raw = _storage?.getString(_quarantineKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _quarantineEntry(Object? record, Object error) => {
    'record': record,
    'reason': error.toString(),
    'quarantinedAt': _clock().toUtc().toIso8601String(),
  };

  List<CustomSource> _dedupeSources(List<CustomSource> sources) {
    if (sources.isEmpty) return const [];
    final seenIds = <String>{};
    final seenNameAuthor = <String>{};
    final kept = <CustomSource>[];

    final ordered = [...sources]
      ..sort((a, b) {
        if (a.isEnabled != b.isEnabled) return a.isEnabled ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

    for (final s in ordered) {
      final key = '${s.name}|${s.author}'.toLowerCase();
      if (seenIds.contains(s.id) || seenNameAuthor.contains(key)) {
        continue;
      }
      seenIds.add(s.id);
      seenNameAuthor.add(key);
      kept.add(s);
    }
    return kept;
  }

  Future<void> _saveSources(List<CustomSource> sources) async {
    final jsonList = sources.map((s) => s.toJson()).toList();
    await _storage!.setString(_storageKey, json.encode(jsonList));
  }

  Future<T> _mutate<T>(
    _SourceMutation<T> Function(List<CustomSource> current) calculate,
  ) {
    final operation = _mutationTail.then((_) async {
      final mutation = calculate(List<CustomSource>.of(_sources));
      final sources = mutation.sources
          .map(
            (source) =>
                source.isEnabled &&
                    script_safety.hasUnsafeSynchronousLoop(source.script)
                ? source.copyWith(isEnabled: false)
                : source,
          )
          .toList();
      await _saveSources(sources);
      _publish(sources);
      for (final id in mutation.invalidateEngines) {
        _engines[id]?.dispose();
        _engines.remove(id);
      }
      return mutation.result;
    });
    _mutationTail = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  void _publish(List<CustomSource> sources) {
    _sources
      ..clear()
      ..addAll(sources);
    _revisionController.add(++_revision);
  }

  Future<void> replaceAllSources(List<CustomSource> sources) async {
    await _mutate<void>(
      (current) => _SourceMutation(_dedupeSources(sources), null),
    );
  }

  Future<void> addSource(CustomSource source) async {
    await _mutate<void>(
      (current) => _SourceMutation(_dedupeSources([...current, source]), null),
    );
  }

  Future<void> updateSource(CustomSource source) async {
    await _mutate<void>((current) {
      final index = current.indexWhere((item) => item.id == source.id);
      if (index < 0) return _SourceMutation(current, null);
      current[index] = source.copyWith(updatedAt: DateTime.now());
      return _SourceMutation(
        _dedupeSources(current),
        null,
        invalidateEngines: {source.id},
      );
    });
  }

  Future<void> deleteSource(String id) async {
    await _mutate<void>(
      (current) => _SourceMutation(
        current.where((source) => source.id != id).toList(),
        null,
        invalidateEngines: {id},
      ),
    );
  }

  /// 切换源启用状态。启用时会立即初始化引擎（官方行为），
  /// 返回初始化是否成功；禁用返回 true。
  Future<bool> toggleSource(String id) async {
    final int index = _sources.indexWhere((source) => source.id == id);
    final CustomSource? target = index >= 0 ? _sources[index] : null;
    if (target == null) return true;
    final bool willEnable = !target.isEnabled;
    if (willEnable && script_safety.hasUnsafeSynchronousLoop(target.script)) {
      return false;
    }
    final previouslyEnabled = _sources
        .where((source) => source.isEnabled)
        .map((source) => source.id)
        .toSet();
    await _mutate<void>((current) {
      final curIndex = current.indexWhere((source) => source.id == id);
      if (curIndex >= 0) {
        for (int i = 0; i < current.length; i++) {
          if (i == curIndex) {
            current[i] = current[i].copyWith(
              isEnabled: willEnable,
              updatedAt: DateTime.now(),
            );
          } else if (willEnable) {
            current[i] = current[i].copyWith(isEnabled: false);
          }
        }
      }
      return _SourceMutation(current, null);
    });
    // 启用时立即初始化引擎（真实加载脚本并注册 handler），
    // 而不是等到第一次请求才懒加载。
    if (willEnable) {
      final engine = _getEngine(id);
      try {
        final loaded = await engine.loadSource(target);
        if (loaded) return true;
      } catch (_) {
        // Failed initialization is rolled back below.
      }
      await _mutate<void>((current) {
        for (var i = 0; i < current.length; i++) {
          current[i] = current[i].copyWith(
            isEnabled: previouslyEnabled.contains(current[i].id),
          );
        }
        return _SourceMutation(current, null, invalidateEngines: {id});
      });
      return false;
    }
    return true;
  }

  CustomSourceEngine _getEngine(String sourceId) {
    if (!_engines.containsKey(sourceId)) {
      _engines[sourceId] = CustomSourceEngine();
    }
    return _engines[sourceId]!;
  }

  Stream<Map<String, dynamic>> getEventStream(String sourceId) {
    return _getEngine(sourceId).eventStream;
  }

  Future<String?> effectiveMusicQuality(
    String sourceId,
    String platform,
    String requested,
  ) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0 || !_sources[index].isEnabled) return null;
    final source = _sources[index];
    final engine = _getEngine(sourceId);
    if (!await engine.loadSource(source)) return null;
    return engine.effectiveMusicQuality(platform, requested);
  }

  Future<List<MusicItem>> searchWithSource(
    String sourceId,
    String keyword, {
    String source = 'kw',
    int page = 1,
    int limit = 20,
    String type = 'music',
  }) async {
    final customSource = _sources.firstWhere(
      (s) => s.id == sourceId,
      orElse: () => throw Exception('源不存在'),
    );
    if (!customSource.isEnabled) return [];
    try {
      final engine = _getEngine(sourceId);
      await engine.loadSource(customSource);
      return await engine.search(
        keyword,
        source: source,
        page: page,
        limit: limit,
        type: type,
      );
    } catch (e) {
      return [];
    }
  }

  Future<String?> getMusicUrl(
    String sourceId,
    MusicItem music, {
    String quality = '320k',
  }) async {
    final detailed = await getMusicUrlDetailed(
      sourceId,
      music,
      quality: quality,
    );
    return detailed?.url;
  }

  Future<({String url, String? type})?> getMusicUrlDetailed(
    String sourceId,
    MusicItem music, {
    String quality = '320k',
  }) async {
    try {
      final customSource = _sources.firstWhere(
        (s) => s.id == sourceId,
        orElse: () => throw Exception('源不存在'),
      );
      if (!customSource.isEnabled) return null;
      if (customSource.script.trim().isEmpty) {
        throw Exception('源脚本为空: ${customSource.name}');
      }
      final engine = _getEngine(sourceId);
      final loaded = await engine.loadSource(customSource);
      if (!loaded) {
        throw Exception('源脚本加载失败: ${customSource.name}');
      }
      return await engine.getMusicUrlDetailed(music, quality: quality);
    } catch (e) {
      // 向上抛出由调用方记录；勿静默吞掉导致“源没生效”难排查
      rethrow;
    }
  }

  Future<String?> getLyric(String sourceId, MusicItem music) async {
    try {
      final customSource = _sources.firstWhere(
        (s) => s.id == sourceId,
        orElse: () => throw Exception('源不存在'),
      );
      if (!customSource.isEnabled) return null;
      final engine = _getEngine(sourceId);
      await engine.loadSource(customSource);
      return await engine.getLyric(music);
    } catch (e) {
      return null;
    }
  }

  Future<List<MusicItem>> getSongListDetail(
    String sourceId,
    String id, {
    String source = 'kw',
    int page = 1,
  }) async {
    try {
      final customSource = _sources.firstWhere(
        (s) => s.id == sourceId,
        orElse: () => throw Exception('源不存在'),
      );
      if (!customSource.isEnabled) return [];
      final engine = _getEngine(sourceId);
      final loaded = await engine.loadSource(customSource);
      if (!loaded) return [];
      return await engine.getSongListDetail(id, source: source, page: page);
    } catch (e) {
      return [];
    }
  }

  Future<bool> importSource(String jsonStr) async {
    if (_exceedsScriptByteLimit(jsonStr)) return false;
    try {
      final json = jsonDecode(jsonStr);
      final source = CustomSource.fromJson(json as Map<String, dynamic>);
      final now = _clock();
      return await _mutate<bool>((current) {
        final index = current.indexWhere((item) => item.id == source.id);
        final invalidated = <String>{};
        if (index >= 0) {
          current[index] = source.copyWith(updatedAt: now);
          invalidated.add(source.id);
        } else {
          current.add(source);
        }
        return _SourceMutation(
          _dedupeSources(current),
          true,
          invalidateEngines: invalidated,
        );
      });
    } catch (e) {
      return false;
    }
  }

  Future<bool> importLxMusicScript(String script) async {
    if (_exceedsScriptByteLimit(script)) return false;
    if (!validateScript(script)) return false;
    try {
      final header = parseSourceScriptHeader(script)!;
      final name = header['name'] ?? '未命名音源';
      final description = header['description'] ?? '';
      final version = header['version'] ?? '1.0.0';
      final author = header['author'] ?? '未知';

      return await _mutate<bool>((current) {
        final now = _clock();
        final shouldEnable =
            !script_safety.hasUnsafeSynchronousLoop(script) &&
            !current.any((source) => source.isEnabled);
        final candidate = CustomSource(
          id: now.microsecondsSinceEpoch.toString(),
          name: name,
          description: description,
          version: version,
          author: author,
          script: script,
          createdAt: now,
          updatedAt: now,
          isEnabled: shouldEnable,
        );
        final invalidated = <String>{};
        late final String targetId;
        final existingIndex = current.indexWhere(
          (source) => source.name == name && source.author == author,
        );
        if (existingIndex >= 0) {
          final old = current[existingIndex];
          current[existingIndex] = old.copyWith(
            description: description,
            version: version,
            script: script,
            updatedAt: now,
            isEnabled: old.isEnabled || shouldEnable,
          );
          targetId = old.id;
          invalidated.add(old.id);
        } else {
          current.add(candidate);
          targetId = candidate.id;
        }
        if (current.any(
          (source) => source.id == targetId && source.isEnabled,
        )) {
          for (var i = 0; i < current.length; i++) {
            if (current[i].id != targetId && current[i].isEnabled) {
              current[i] = current[i].copyWith(isEnabled: false);
            }
          }
        }
        return _SourceMutation(
          _dedupeSources(current),
          true,
          invalidateEngines: invalidated,
        );
      });
    } catch (e) {
      return false;
    }
  }

  Future<bool> importSourceFromUrl(
    String url, {
    SourceRequestCancellation? cancellation,
  }) async {
    final cancel = cancellation ?? SourceRequestCancellation();
    try {
      final importUri = Uri.tryParse(url.trim());
      if (importUri == null ||
          importUri.scheme.toLowerCase() != 'https' ||
          importUri.host.isEmpty ||
          importUri.userInfo.isNotEmpty) {
        return false;
      }
      return await () async {
        final response = await _importSandbox.request(importUri, const {
          'method': 'GET',
          'timeout': 15000,
          'httpsOnly': true,
        }, cancellation: cancel);
        final script = await withSourceResponseLease(response, (owned) async {
          if (owned.statusCode != 200) return null;
          return utf8.decode(owned.bytes, allowMalformed: false);
        });
        if (script == null || !validateScript(script)) return false;
        // Import validation only filters non-source content. Imported scripts
        // are retained disabled because the current JS engine cannot enforce
        // an execution deadline on every supported platform.
        return await importLxMusicScript(script);
      }().timeout(
        importTimeout,
        onTimeout: () {
          cancel.cancel('import timeout');
          return false;
        },
      );
    } catch (_) {
      if (!cancel.isCancelled) cancel.cancel('import failed');
      return false;
    }
  }

  String exportSource(String id) {
    final source = _sources.firstWhere((s) => s.id == id);
    return json.encode(source.toJson());
  }

  String exportAllSources() {
    final jsonList = _sources.map((s) => s.toJson()).toList();
    return json.encode(jsonList);
  }

  /// 校验音源脚本。与洛雪桌面端（`parseScriptInfo`）保持一致：
  /// 只要求脚本以 `/* ... */` 文件头注释开头，并从中解析出 `@name` 元数据，
  /// **不检查正文内容关键字**。
  ///
  /// 为什么这么宽松：
  /// - 音源脚本经常用 obfuscator.io / Unicode 变量名混淆（如 sixyin、lx），
  ///   混淆后正文不含 `EVENT_NAMES` / `musicUrl` 等明文关键字。
  ///   若校验正文关键字，这些能正常运行的源会被误拒（Windows 桌面端可用，
  ///   仅移动端被拦）。
  /// - 洛雪桌面端同样只做文件头校验，我们与其对齐，保证同一份源在两个端
  ///   行为一致。
  ///
  /// 文件头和正文启发式都不是沙箱。脚本可以导入和导出，但在运行时具备
  /// 可中断的执行期限之前保持禁用。
  /// - 文件头 `@name` 同时是导入后元数据（名称/作者/版本）的来源，要求它
  ///   存在可过滤掉纯文本、无注释的普通 JS 等非音源内容。
  bool validateScript(String script) {
    return isValidSourceScript(script);
  }

  static bool hasUnsafeSynchronousLoop(String script) =>
      script_safety.hasUnsafeSynchronousLoop(script);

  void dispose() {
    for (final engine in _engines.values) {
      engine.dispose();
    }
    _engines.clear();
    _revisionController.close();
  }
}

final class _SourceMutation<T> {
  const _SourceMutation(
    this.sources,
    this.result, {
    this.invalidateEngines = const {},
  });

  final List<CustomSource> sources;
  final T result;
  final Set<String> invalidateEngines;
}
