import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cloud/domain/cloud_api_client.dart';
import '../../custom_source/domain/custom_source.dart';
import '../../playlist/domain/playlist.dart';
import '../../playlist/domain/playlist_service.dart';
import '../presentation/cloud_playlist_merge.dart';

enum CloudSyncChoice { cloud, local, merge }

final class CloudSyncResult {
  const CloudSyncResult({
    required this.revision,
    required this.favoriteCount,
    required this.playlistCount,
    required this.settingsCount,
    required this.sourceCount,
  });

  final int revision;
  final int favoriteCount;
  final int playlistCount;
  final int settingsCount;
  final int sourceCount;
}

typedef SettingsReader = Map<String, String> Function();
typedef SettingsApplier = Future<void> Function(Map<String, String> settings);
typedef SourcesReader = List<CustomSource> Function();
typedef SourcesApplier = Future<void> Function(List<CustomSource> sources);

final class CloudSyncCoordinator {
  CloudSyncCoordinator({
    required this.api,
    required this.service,
    this.readSettings,
    this.applySettings,
    this.readSources,
    this.applySources,
    this.onStage,
    this.onApplyingRemote,
  });

  final CloudApiClient api;
  final PlaylistService service;
  final SettingsReader? readSettings;
  final SettingsApplier? applySettings;
  final SourcesReader? readSources;
  final SourcesApplier? applySources;
  void Function(String stage)? onStage;
  void Function(bool applying)? onApplyingRemote;

  Future<bool> remoteChanged() async {
    final baseline = await _readBaseline();
    if (baseline == null) return true;
    return await api.fetchSyncRevision() != baseline.revision;
  }

  Future<CloudSyncResult> sync({CloudSyncChoice? choice}) async {
    onStage?.call('读取云端数据');
    final sessionRevision = api.sessionRevision;
    final cloud = await api.fetchUserList();
    _requireSession(sessionRevision);
    _validateCloud(cloud);
    final cloudRevision = (cloud['revision'] as num?)?.toInt() ?? 0;
    onStage?.call('合并本地收藏与歌单');
    final local = await service.getAllPlaylists();

    // 歌单始终合并（取并集去重），不弹冲突
    if (choice == null || choice == CloudSyncChoice.merge) {
      onStage?.call('合并本地与云端');
      await _whileApplyingRemote(
        () => mergeAndPersistCloudPlaylists(
          service: service,
          love: (cloud['loveList'] as List?) ?? const [],
          userList: (cloud['userList'] as List?) ?? const [],
          decodeSong: decodeCloudSong,
          syncable: false,
        ),
      );
    } else if (choice == CloudSyncChoice.cloud) {
      _requireSession(sessionRevision);
      await _applyCloud(cloud, local);
    }

    final selected = await service.getAllPlaylists();
    final cloudHash = _hash(_normalizedCloudPayload(cloud));
    final selectedHash = choice == CloudSyncChoice.cloud
        ? cloudHash
        : _hash(_payload(selected));

    final needsPlaylistWrite =
        choice != CloudSyncChoice.cloud && selectedHash != cloudHash;
    if (needsPlaylistWrite) onStage?.call('上传收藏与歌单');
    final playlistRevision = !needsPlaylistWrite
        ? cloudRevision
        : await _replaceCloud(cloud, selected, cloudRevision, sessionRevision);
    _requireSession(sessionRevision);
    await _writeBaseline(selectedHash, playlistRevision);
    final favoriteCount = service.favorites?.songCount ?? 0;
    final playlistCount = _custom(await service.getAllPlaylists()).length;

    final stateResult = await _syncState(
      choice: choice,
      sessionRevision: sessionRevision,
      playlistRevision: playlistRevision,
    );
    // Settings/sources may advance the shared cloud revision. Keep the
    // playlist baseline on that final revision to avoid an 8-second loop.
    await _writeBaseline(selectedHash, stateResult.revision);
    return CloudSyncResult(
      revision: stateResult.revision,
      favoriteCount: favoriteCount,
      playlistCount: playlistCount,
      settingsCount: stateResult.settingsCount,
      sourceCount: stateResult.sourceCount,
    );
  }

  Future<({int revision, int settingsCount, int sourceCount})> _syncState({
    required CloudSyncChoice? choice,
    required int sessionRevision,
    required int playlistRevision,
  }) async {
    if (readSettings == null && readSources == null) {
      return (revision: playlistRevision, settingsCount: 0, sourceCount: 0);
    }
    onStage?.call('同步设置与自定义音源');
    final cloudState = await api.fetchSyncState();
    _requireSession(sessionRevision);
    final cloudRevision = (cloudState['revision'] as num?)?.toInt() ?? 0;
    final cloudSettings = _parseSettings(cloudState['settings']);
    final cloudSources = _parseSources(cloudState['sources']);
    final localSettings = readSettings != null
        ? readSettings!()
        : <String, String>{};
    final localSources = readSources != null
        ? readSources!()
        : <CustomSource>[];

    // 设置合并：首次登录（无 baseline）时，如果本地改过默认值就以本地为准，
    // 否则用云端。后续同步始终合并（本地优先覆盖云端同 key）。
    final stateBaseline = await _readStateBaseline();
    final isFirstSync = stateBaseline == null;
    final mergedSettings = isFirstSync && _hasNonDefaultSettings(localSettings)
        ? {...cloudSettings, ...localSettings}
        : {...localSettings, ...cloudSettings};

    // 音源合并：取并集，本地优先（同 id 用本地覆盖云端）；
    // 跨设备累积的"同名同作者"不同 id 副本只保留最新一条，
    // 避免同一音源在云端越积越多（线上出现 5 个同名源）。
    final mergedSourceMap = {for (final s in cloudSources) s.id: s};
    for (final s in localSources) {
      mergedSourceMap[s.id] = s;
    }
    var mergedSources = mergedSourceMap.values.toList();
    mergedSources = _dedupeSameNameAuthor(mergedSources);

    // 应用合并结果到本地
    await _whileApplyingRemote(() async {
      if (choice != CloudSyncChoice.cloud) {
        if (applySettings != null) await applySettings!(mergedSettings);
        if (applySources != null) await applySources!(mergedSources);
      } else {
        if (applySettings != null) await applySettings!(cloudSettings);
        if (applySources != null) await applySources!(cloudSources);
      }
    });

    // 上传到云端
    final uploadSettings = choice == CloudSyncChoice.cloud
        ? cloudSettings
        : mergedSettings;
    final uploadSources = choice == CloudSyncChoice.cloud
        ? cloudSources
        : mergedSources;

    final cloudStateHash = _hash({
      'settings': cloudSettings,
      'sources': [for (final s in cloudSources) s.toJson()],
    });
    final uploadStateHash = _hash({
      'settings': uploadSettings,
      'sources': [for (final s in uploadSources) s.toJson()],
    });
    final needsStateWrite =
        choice != CloudSyncChoice.cloud && uploadStateHash != cloudStateHash;
    final stateRevision = needsStateWrite
        ? await api.replaceSyncState(
            baseRevision: cloudRevision,
            settings: uploadSettings,
            sources: [for (final s in uploadSources) s.toJson()],
          )
        : cloudRevision;
    _requireSession(sessionRevision);
    await _writeStateBaseline(uploadStateHash, stateRevision);
    return (
      revision: stateRevision,
      settingsCount: uploadSettings.length,
      sourceCount: uploadSources.length,
    );
  }

  /// 检测本地设置是否改过默认值（用户可能使用一段时间后才登录同步）
  static const _defaultSettings = {
    'theme_mode': '0',
    'audio_quality': '1',
    'download_quality': '1',
    'wifi_only_download': 'true',
    'auto_resume_playback': 'false',
    'default_search_platform': 'tx',
  };

  bool _hasNonDefaultSettings(Map<String, String> local) {
    for (final entry in _defaultSettings.entries) {
      if (local[entry.key] != null && local[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  Future<T> _whileApplyingRemote<T>(Future<T> Function() operation) async {
    onApplyingRemote?.call(true);
    try {
      return await operation();
    } finally {
      onApplyingRemote?.call(false);
    }
  }

  Map<String, String> _parseSettings(dynamic raw) {
    if (raw is! Map) return {};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      result[entry.key.toString()] = entry.value.toString();
    }
    return result;
  }

  /// 同名同作者的不同 id 副本只保留最新一条（跨设备去重）。
  static List<CustomSource> _dedupeSameNameAuthor(
    List<CustomSource> sources,
  ) {
    final byKey = <String, CustomSource>{};
    for (final s in sources) {
      final key = '${s.name}|${s.author}'.toLowerCase();
      final existing = byKey[key];
      if (existing == null || !s.updatedAt.isBefore(existing.updatedAt)) {
        byKey[key] = s;
      }
    }
    return byKey.values.toList();
  }

  List<CustomSource> _parseSources(dynamic raw) {
    if (raw is! List) return const [];
    final sources = <CustomSource>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final normalized = Map<String, dynamic>.from(item);
        final fallback = DateTime.now().toUtc().toIso8601String();
        normalized['createdAt'] ??= normalized['updatedAt'] ?? fallback;
        normalized['updatedAt'] ??= normalized['createdAt'] ?? fallback;
        sources.add(CustomSource.fromJson(normalized));
      } catch (error) {
        onStage?.call('跳过一条无效的云端音源记录：$error');
      }
    }
    return sources;
  }

  String get _statePrefix => '${_prefix}_state';

  void _validateCloud(Map<String, dynamic> cloud) {
    if (cloud['complete'] != true) {
      throw StateError('云端歌单快照不完整，已停止同步以保护本地数据');
    }
    final love = cloud['loveList'];
    final userList = cloud['userList'];
    if (love is! List || userList is! List) {
      throw const FormatException('云端歌单响应格式无效');
    }
    for (var index = 0; index < love.length; index++) {
      decodeCloudSong(love[index]);
    }
    final ids = <String>{};
    for (var index = 0; index < userList.length; index++) {
      final raw = userList[index];
      if (raw is! Map) {
        throw FormatException('云端歌单 [$index] 格式无效');
      }
      final id = raw['id']?.toString() ?? '';
      final name = raw['name']?.toString() ?? '';
      final songs = raw['list'];
      if (id.isEmpty ||
          const {'love', 'favorites', 'recent', 'local'}.contains(id) ||
          id.startsWith('__stage__:') ||
          !ids.add(id) ||
          name.isEmpty ||
          songs is! List) {
        throw FormatException('云端歌单 [$index] 数据无效');
      }
      for (var songIndex = 0; songIndex < songs.length; songIndex++) {
        decodeCloudSong(songs[songIndex]);
      }
    }
  }

  Map<String, dynamic> _payload(List<Playlist> playlists) {
    Playlist? favorites;
    for (final playlist in playlists) {
      if (playlist.id == 'favorites') favorites = playlist;
    }
    return {
      'loveList': [
        for (final song in favorites?.songs ?? const []) encodeCloudSong(song),
      ],
      'userList': encodeCloudPlaylists(playlists),
    };
  }

  Map<String, dynamic> _normalizedCloudPayload(Map<String, dynamic> cloud) => {
    'loveList': [
      for (final song in _cloudFavorites(cloud))
        encodeCloudSong(decodeCloudSong(song)),
    ],
    'userList': [
      for (final raw in (cloud['userList'] as List).cast<Map>())
        {
          'id': raw['id'].toString(),
          'name': raw['name'].toString(),
          'list': [
            for (final song in raw['list'] as List)
              encodeCloudSong(decodeCloudSong(song)),
          ],
        },
    ],
  };

  Future<int> _replaceCloud(
    Map<String, dynamic> cloud,
    List<Playlist> local,
    int revision,
    int sessionRevision,
  ) async {
    final payload = _payload(local);
    return api.replaceCloudSnapshot(
      loveList: (payload['loveList'] as List).cast<Map<String, dynamic>>(),
      userList: (payload['userList'] as List).cast<Map<String, dynamic>>(),
      baseRevision: revision,
      expectedSessionRevision: sessionRevision,
    );
  }

  void _requireSession(int expected) {
    if (api.sessionRevision != expected) {
      throw const CloudSessionSafetyError('云端账号已切换，本次同步已取消');
    }
  }

  Future<void> _applyCloud(
    Map<String, dynamic> cloud,
    List<Playlist> local,
  ) async {
    final now = DateTime.now();
    final current = {for (final playlist in local) playlist.id: playlist};
    final playlists = <Playlist>[];
    final favorites = [
      for (final raw in _cloudFavorites(cloud)) decodeCloudSong(raw),
    ];
    playlists.add(
      (current['favorites'] ??
              Playlist(
                id: 'favorites',
                name: '收藏列表',
                songs: const [],
                createdAt: now,
                updatedAt: now,
              ))
          .copyWith(songs: favorites, updatedAt: now),
    );
    for (final raw in (cloud['userList'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final id = raw['id']?.toString() ?? '';
      final list = raw['list'];
      if (id.isEmpty || list is! List) continue;
      playlists.add(
        Playlist(
          id: id,
          name: raw['name']?.toString() ?? id,
          description: '云端同步',
          songs: [for (final song in list) decodeCloudSong(song)],
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    playlists.addAll(
      [current['recent'], current['local']].whereType<Playlist>(),
    );
    await _whileApplyingRemote(
      () => service.replaceAll(playlists, syncable: false),
    );
  }

  List<Playlist> _custom(Iterable<Playlist> playlists) => [
    for (final playlist in playlists)
      if (!const {'favorites', 'recent', 'local'}.contains(playlist.id))
        playlist,
  ];

  List<dynamic> _cloudFavorites(Map<String, dynamic> cloud) =>
      (cloud['loveList'] as List?) ?? const [];

  String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  String get _prefix =>
      'cloud_sync_${sha256.convert(utf8.encode('${api.baseUrl}|${api.username}')).toString().substring(0, 16)}';

  Future<({String hash, int revision})?> _readBaseline() async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString('${_prefix}_hash');
    final revision = prefs.getInt('${_prefix}_revision');
    return hash == null || revision == null
        ? null
        : (hash: hash, revision: revision);
  }

  Future<void> _writeBaseline(String hash, int revision) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefix}_hash', hash);
    await prefs.setInt('${_prefix}_revision', revision);
  }

  Future<({String hash, int revision})?> _readStateBaseline() async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString('$_statePrefix\_hash');
    final revision = prefs.getInt('$_statePrefix\_revision');
    return hash == null || revision == null
        ? null
        : (hash: hash, revision: revision);
  }

  Future<void> _writeStateBaseline(String hash, int revision) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_statePrefix\_hash', hash);
    await prefs.setInt('$_statePrefix\_revision', revision);
  }
}
