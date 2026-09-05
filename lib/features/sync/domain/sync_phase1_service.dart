import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

import '../../cloud/domain/cloud_api_client.dart';
import '../data/sync_cursor_store.dart';
import '../data/sync_identity_store.dart';
import '../data/sync_outbox_repository.dart';
import 'sync_account.dart';
import 'sync_event.dart';
import '../../playlist/domain/playlist_service.dart';
import '../../playlist/domain/playlist.dart';
import '../../player/domain/music_item.dart';
import '../domain/rating_store.dart';
import '../../custom_source/domain/custom_source.dart';
import '../../custom_source/domain/custom_source_service.dart';

final class SyncReport {
  const SyncReport({
    required this.deviceId,
    required this.completedAt,
    required this.counts,
  });
  final String deviceId;
  final DateTime completedAt;
  final Map<String, int> counts;

  static Future<SyncReport> fromCurrentState({
    required String deviceId,
    required PlaylistService playlists,
    required RatingStore ratings,
    required CustomSourceService sources,
    required DateTime completedAt,
  }) async {
    final allPlaylists = await playlists.getAllPlaylists();
    final favorite = await playlists.getAllSongs('favorites');
    return SyncReport(
      deviceId: deviceId,
      completedAt: completedAt,
      counts: {
        '收藏歌曲': favorite.length,
        '普通歌单': allPlaylists
            .where(
              (item) => !{'favorites', 'recent', 'local'}.contains(item.id),
            )
            .length,
        '评分': (await ratings.load()).length,
        '设置': 6,
        '自定义音源': sources.sources.length,
      },
    );
  }

  factory SyncReport.fromEvents({
    required String deviceId,
    required List<SyncEvent> uploaded,
    required List<Map<String, dynamic>> downloaded,
    required DateTime completedAt,
  }) {
    final counts = <String, int>{};
    for (final event in [...uploaded, ...downloaded.map(_eventFromRemote)]) {
      final key = _resourceName(event.eventType);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return SyncReport(
      deviceId: deviceId,
      completedAt: completedAt,
      counts: counts,
    );
  }
}

String _resourceName(String type) => switch (type) {
  'favorite.add' || 'favorite.remove' => '收藏',
  'playlist.create' ||
  'playlist.rename' ||
  'playlist.delete' ||
  'playlist_item.add' ||
  'playlist_item.remove' ||
  'playlist_item.move' => '歌单',
  'rating.set' || 'rating.remove' => '评分',
  'setting.set' => '设置',
  'custom_source.upsert' || 'custom_source.remove' => '自定义音源',
  _ => '其他',
};

SyncEvent _eventFromRemote(Map<String, dynamic> raw) => SyncEvent(
  eventId: raw['eventId']?.toString() ?? '',
  localUserId: raw['localUserId']?.toString() ?? '',
  deviceId: raw['deviceId']?.toString() ?? '',
  accountId: null,
  eventType: raw['eventType']?.toString() ?? '',
  entityId: raw['entityId']?.toString() ?? '',
  payload: raw['payload'] is Map
      ? Map<String, dynamic>.from(raw['payload'])
      : const {},
  createdAt: DateTime.fromMillisecondsSinceEpoch(
    (raw['createdAt'] as num?)?.toInt() ?? 0,
    isUtc: true,
  ),
);

final class SyncPhase1Service {
  SyncPhase1Service({
    required this.api,
    SyncIdentityStore? identity,
    SyncOutboxRepository? outbox,
    SyncCursorStore? cursor,
  }) : identity = identity ?? SyncIdentityStore(),
       outbox = outbox ?? SyncOutboxRepository(),
       cursor = cursor ?? SyncCursorStore();

  final CloudApiClient api;
  final SyncIdentityStore identity;
  final SyncOutboxRepository outbox;
  final SyncCursorStore cursor;
  PlaylistService? _playlists;
  RatingStore? _ratings;
  Future<void> Function(String key, String value)? _settingApplier;
  CustomSourceService? _sources;
  void Function(bool applying)? onApplyingRemote;
  void Function(String message)? onProgress;
  void Function(SyncEvent event)? onLocalEventRecorded;

  void attachPlaylists(PlaylistService service) {
    _playlists = service;
  }

  void attachRatings(RatingStore store) => _ratings = store;
  void attachSettingApplier(
    Future<void> Function(String key, String value) applier,
  ) => _settingApplier = applier;
  void attachSources(CustomSourceService service) => _sources = service;

  final Uuid _uuid = const Uuid();

  Future<SyncAccount> account() => identity.load();

  Future<SyncEvent> enqueue({
    required String eventType,
    required String entityId,
    Map<String, dynamic> payload = const {},
  }) async {
    final account = await identity.load();
    final event = SyncEvent(
      eventId: 'evt_${_uuid.v4()}',
      localUserId: account.localUserId,
      deviceId: account.deviceId,
      accountId: account.accountId,
      eventType: eventType,
      entityId: entityId,
      payload: payload,
      createdAt: DateTime.now().toUtc(),
    );
    await outbox.append(event);
    onLocalEventRecorded?.call(event);
    return event;
  }

  Future<void> recordSetting(String key, String value) async {
    await enqueue(
      eventType: 'setting.set',
      entityId: key,
      payload: {'value': value},
    );
  }

  Future<void> recordSource(CustomSource source) async {
    // 启用状态是本设备偏好，不上传到云端（避免 A 设备的启用状态
    // 被同步到 B 设备导致"同时启用多个音源"）。
    final definition = source.copyWith(isEnabled: false).toJson();
    await enqueue(
      eventType: 'custom_source.upsert',
      entityId: source.id,
      payload: {'source': definition},
    );
  }

  Future<void> recordSourceRemoval(String id) async {
    await enqueue(eventType: 'custom_source.remove', entityId: id);
  }

  Future<int> pendingCount() async => (await outbox.load()).length;

  Future<SyncReport?> pushLocalEventsOnly() async {
    if (!api.isLoggedIn) return null;
    final account = await identity.load();
    final uploaded = await push();
    return SyncReport.fromEvents(
      deviceId: account.deviceId,
      uploaded: uploaded,
      downloaded: const [],
      completedAt: DateTime.now().toUtc(),
    );
  }

  Future<List<SyncEvent>> push() async {
    final account = await identity.load();
    if (!api.isLoggedIn) return const [];
    final events = await outbox.load();
    final eligible = events
        .where((event) {
          if (event.accountId == account.accountId) return true;
          // Anonymous events are the only local events eligible for the first
          // merge into a newly authenticated account.
          return event.accountId == null;
        })
        .toList(growable: false);
    if (eligible.isEmpty) return const [];
    final uploaded = <SyncEvent>[];
    final batches = _byteBoundedEventBatches(
      deviceId: account.deviceId,
      events: eligible,
    ).toList(growable: false);
    var completedEvents = 0;
    for (var index = 0; index < batches.length; index++) {
      final batch = batches[index];
      final favoriteCount = batch
          .where((event) => event.eventType == 'favorite.add')
          .length;
      onProgress?.call(
        favoriteCount > 0
            ? '上传收藏：第 ${index + 1}/${batches.length} 批，已处理 $completedEvents/${eligible.length} 条，当前批 $favoriteCount 首'
            : '上传变更：第 ${index + 1}/${batches.length} 批',
      );
      final result = await api.pushSyncEvents(
        deviceId: account.deviceId,
        events: [for (final event in batch) event.toJson()],
      );
      final accepted =
          (result['acceptedEventIds'] as List?)
              ?.map((value) => value.toString())
              .toSet() ??
          const <String>{};
      await outbox.removeProcessed(accepted);
      uploaded.addAll(batch.where((event) => accepted.contains(event.eventId)));
      completedEvents += accepted.length;
    }
    // Do not advance the pull cursor from a push response. Pull must start at
    // the previous cursor so remote-device events are not skipped; only a
    // successful pull may advance the cursor.
    return uploaded;
  }

  Iterable<List<SyncEvent>> _byteBoundedEventBatches({
    required String deviceId,
    required List<SyncEvent> events,
  }) sync* {
    // Workers rejects request bodies over 256 KiB. Keep enough headroom for
    // JSON wrapper fields and encoding differences between platforms.
    const maximumBytes = 220 * 1024;
    const maximumEvents = 180;
    var batch = <SyncEvent>[];
    for (final event in events) {
      final candidate = [...batch, event];
      final bytes = utf8
          .encode(
            jsonEncode({
              'deviceId': deviceId,
              'events': [for (final item in candidate) item.toJson()],
            }),
          )
          .length;
      if (bytes <= maximumBytes && candidate.length <= maximumEvents) {
        batch = candidate;
        continue;
      }
      if (batch.isEmpty) {
        throw StateError('单条同步事件超过 220 KiB：${event.eventType}');
      }
      yield batch;
      batch = [event];
      final singleBytes = utf8
          .encode(
            jsonEncode({
              'deviceId': deviceId,
              'events': [event.toJson()],
            }),
          )
          .length;
      if (singleBytes > maximumBytes) {
        throw StateError('单条同步事件超过 220 KiB：${event.eventType}');
      }
    }
    if (batch.isNotEmpty) yield batch;
  }

  Future<SyncReport?> sync() async {
    if (!api.isLoggedIn) return null;
    var account = await identity.load();
    final firstSync =
        account.state == SyncAccountState.anonymous ||
        account.state == SyncAccountState.authenticated;
    if (firstSync) await cursor.clear();
    if (account.state == SyncAccountState.anonymous) {
      account = await identity.setState(
        account,
        SyncAccountState.authenticated,
        accountId: api.accountId ?? api.username,
      );
    }
    await identity.setState(account, SyncAccountState.merging);
    try {
      final status = await api.fetchSyncAccountStatus();
      final localFavoriteCount = _playlists == null
          ? 0
          : (await _playlists!.getAllSongs('favorites')).length;
      final cloudFavoriteCount =
          (status['favoriteCount'] as num?)?.toInt() ?? 0;
      await _ensureFavoriteBaseline(
        account,
        force: cloudFavoriteCount < localFavoriteCount,
      );
      onProgress?.call('检查云端数据');
      if (firstSync && status['hasCloudData'] == true) {
        // Bootstrap from a compact snapshot. The snapshot cursor is persisted
        // only after every local store has accepted the snapshot, so a failed
        // apply cannot skip remote events. Events created while the snapshot
        // is being read are replayed by the later pull.
        onProgress?.call('下载云端数据');
        await _applyCloudSnapshot();
      }
      await identity.setState(account, SyncAccountState.syncing);
      onProgress?.call('上传本地变更');
      await push();
      onProgress?.call('应用其他设备变更');
      final accountId = account.accountId;
      if (accountId != null &&
          !(await outbox.load()).any(
            (event) =>
                event.accountId == accountId &&
                event.eventId.startsWith('evt_favbase_'),
          )) {
        await identity.markFavoriteBaseline(accountId);
      }
      await _pullAll();
      await identity.markSynced(account);
      return SyncReport.fromCurrentState(
        deviceId: account.deviceId,
        playlists: _playlists!,
        ratings: _ratings!,
        sources: _sources!,
        completedAt: DateTime.now().toUtc(),
      );
    } catch (_) {
      await identity.setState(account, SyncAccountState.syncError);
      rethrow;
    }
  }

  Future<void> _ensureFavoriteBaseline(
    SyncAccount account, {
    bool force = false,
  }) async {
    final accountId = account.accountId;
    final service = _playlists;
    if (accountId == null || service == null) return;
    if (!force && await identity.hasFavoriteBaseline(accountId)) return;
    final favorites = await service.getAllSongs('favorites');
    for (final song in favorites) {
      final digest = sha256
          .convert(utf8.encode('$accountId|${song.identityKey}'))
          .toString()
          .substring(0, 32);
      await outbox.append(
        SyncEvent(
          eventId: 'evt_favbase_$digest',
          localUserId: account.localUserId,
          deviceId: account.deviceId,
          accountId: accountId,
          eventType: 'favorite.add',
          entityId: song.identityKey,
          payload: {'playlistId': 'favorites', 'song': song.toJson()},
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }
    if (favorites.isEmpty) await identity.markFavoriteBaseline(accountId);
  }

  Future<void> fullResync() async {
    if (!api.isLoggedIn) return;
    await _applyCloudSnapshot();
    await _pullAll();
    await identity.markSynced(await identity.load());
  }

  Future<void> _applyCloudSnapshot() async {
    final snapshot = await api.fetchSyncSnapshot();
    final snapshotCursor = (snapshot['cursor'] as num?)?.toInt();
    if (snapshotCursor == null || snapshotCursor < 0) {
      throw const FormatException('sync snapshot cursor invalid');
    }
    await _applySnapshot(snapshot);
    await cursor.write(snapshotCursor);
  }

  Future<void> _applySnapshot(Map<String, dynamic> snapshot) async {
    final service = _playlists;
    if (service == null ||
        _ratings == null ||
        _sources == null ||
        _settingApplier == null) {
      throw StateError('同步目标尚未初始化');
    }
    final rawPlaylists = snapshot['playlists'];
    if (rawPlaylists is! List) {
      throw const FormatException('sync snapshot playlists invalid');
    }
    final playlists = <Playlist>[];
    for (final raw in rawPlaylists) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final songs = (map['songs'] is List ? map['songs'] as List : const [])
          .whereType<Map>()
          .map((song) => _song(Map<String, dynamic>.from(song)))
          .whereType<MusicItem>()
          .toList(growable: false);
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      playlists.add(
        Playlist(
          id: id == 'love' ? 'favorites' : id,
          name: map['name']?.toString() ?? id,
          songs: songs,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    await service.withoutSyncRecording(
      () => service.replaceAll(playlists, syncable: false),
    );
    final settings = snapshot['settings'];
    if (settings is Map) {
      for (final entry in settings.entries) {
        await _settingApplier!(entry.key.toString(), entry.value.toString());
      }
    }
    final sources = snapshot['sources'];
    if (sources is List) {
      // 快照同步也只同步"源定义"：本地已存在的源保留本地启用状态，
      // 新增源默认禁用（启用状态是设备本地偏好）。
      final existingById = {for (final s in _sources!.sources) s.id: s};
      await _sources!.replaceAllSources([
        for (final raw in sources)
          if (raw is Map)
            () {
              final remote = CustomSource.fromJson(
                Map<String, dynamic>.from(raw),
              );
              final local = existingById[remote.id];
              if (local != null) {
                return remote.copyWith(isEnabled: local.isEnabled);
              }
              return remote.copyWith(isEnabled: false);
            }(),
      ]);
    }
    final ratings = snapshot['ratings'];
    if (ratings is Map) {
      for (final entry in ratings.entries) {
        await _ratings!.applyRemote(
          entry.key.toString(),
          (entry.value as num).toInt(),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _pullAll() async {
    final all = <Map<String, dynamic>>[];
    while (true) {
      final result = await pull();
      if (result['events'] is List) {
        all.addAll(
          (result['events'] as List).whereType<Map>().map(
            Map<String, dynamic>.from,
          ),
        );
      }
      if (result['hasMore'] != true) return all;
    }
  }

  Future<void> logout({
    bool clearLocalData = false,
    bool Function()? stillCurrent,
  }) async {
    final account = await identity.load();
    if (stillCurrent != null && !stillCurrent()) return;
    if (clearLocalData) {
      if (stillCurrent != null && !stillCurrent()) return;
      final events = await outbox.load();
      await outbox.removeProcessed(events.map((event) => event.eventId));
      if (stillCurrent != null && !stillCurrent()) return;
      await _playlists?.clearSyncableData();
      await _ratings?.clear();
    }
    if (stillCurrent != null && !stillCurrent()) return;
    await cursor.clear();
    await identity.returnToAnonymous(account);
  }

  Future<Map<String, dynamic>> pull() async {
    if (!api.isLoggedIn) return const {};
    Map<String, dynamic> result;
    try {
      result = await api.pullSyncEvents(cursor: await cursor.read());
    } on DioException catch (error) {
      final data = error.response?.data;
      final expired =
          error.response?.statusCode == 409 &&
          data is Map &&
          data['error'] == 'sync_cursor_expired' &&
          data['snapshotRequired'] == true;
      if (!expired) rethrow;
      await _applyCloudSnapshot();
      result = await api.pullSyncEvents(cursor: await cursor.read());
    }
    final applied = await applyPulledEvents(result['events']);
    if (!applied) throw StateError('同步数据尚未准备好，Cursor 未推进');
    final next = (result['cursor'] as num?)?.toInt();
    if (next != null) await cursor.write(next);
    return result;
  }

  Future<bool> applyPulledEvents(dynamic raw) async {
    final service = _playlists;
    if (raw is! List) return false;
    if (service == null ||
        _ratings == null ||
        _settingApplier == null ||
        _sources == null) {
      return false;
    }
    Future<void> apply() async {
      await _applyFavoriteBatch(service, raw);
      for (final item in raw) {
        if (item is! Map) continue;
        final event = Map<String, dynamic>.from(item);
        if (event['eventType'] == 'favorite.add' ||
            event['eventType'] == 'favorite.remove') {
          continue;
        }
        await _applyEvent(service, event);
      }
    }

    onApplyingRemote?.call(true);
    try {
      await service.withoutSyncRecording(apply);
    } finally {
      onApplyingRemote?.call(false);
    }
    return true;
  }

  Future<void> _applyFavoriteBatch(
    PlaylistService service,
    List<dynamic> raw,
  ) async {
    final favorite = service.favorites;
    if (favorite == null) return;
    final songs = [...await service.getAllSongs('favorites')];
    for (final item in raw) {
      if (item is! Map) continue;
      final event = Map<String, dynamic>.from(item);
      final type = event['eventType']?.toString();
      if (type == 'favorite.add') {
        final payload = event['payload'];
        final data = payload is Map
            ? Map<String, dynamic>.from(payload)
            : const <String, dynamic>{};
        final song = _song(data['song']);
        if (song != null &&
            !songs.any((item) => item.identityKey == song.identityKey)) {
          songs.insert(
            0,
            song.copyWith(
              playlistItemId:
                  song.playlistItemId ?? event['entityId']?.toString(),
            ),
          );
        }
      } else if (type == 'favorite.remove') {
        final entityId = event['entityId']?.toString() ?? '';
        songs.removeWhere(
          (song) =>
              song.identityKey == entityId || song.playlistItemId == entityId,
        );
      }
    }
    await service.replaceAll([
      for (final playlist in await service.getAllPlaylists())
        playlist.id == 'favorites'
            ? playlist.copyWith(songs: List.unmodifiable(songs))
            : playlist,
    ], syncable: false);
  }

  Future<void> _applyEvent(
    PlaylistService? service,
    Map<String, dynamic> event,
  ) async {
    final type = event['eventType']?.toString();
    final entityId = event['entityId']?.toString() ?? '';
    final payload = event['payload'];
    final data = payload is Map
        ? Map<String, dynamic>.from(payload)
        : const <String, dynamic>{};
    switch (type) {
      case 'favorite.add':
        if (service == null) return;
        final song = _song(data['song']);
        if (song != null) {
          await service.addSongToPlaylist(
            'favorites',
            song,
            playlistItemId: song.playlistItemId,
          );
        }
      case 'favorite.remove':
        if (service == null) return;
        await service.removeSongFromPlaylist('favorites', entityId);
      case 'playlist.create':
        if (service == null) return;
        if (service.getPlaylist(entityId) == null) {
          await service.createPlaylist(
            id: entityId,
            name: data['name']?.toString() ?? entityId,
            description: data['description']?.toString(),
          );
        }
      case 'playlist.rename':
        if (service == null) return;
        if (service.getPlaylist(entityId) != null) {
          await service.updatePlaylist(
            id: entityId,
            name: data['name']?.toString(),
            description: data['description']?.toString(),
            coverUrl: data['coverUrl']?.toString(),
          );
        }
      case 'playlist.delete':
        if (service == null) return;
        if (service.getPlaylist(entityId) != null) {
          await service.deletePlaylist(entityId);
        }
      case 'playlist_item.add':
        if (service == null) return;
        final playlistId = data['playlistId']?.toString() ?? '';
        final song = _song(data['song']);
        if (playlistId.isNotEmpty &&
            song != null &&
            service.getPlaylist(playlistId) != null) {
          await service.addSongToPlaylist(
            playlistId,
            song,
            playlistItemId: song.playlistItemId,
          );
        }
      case 'playlist_item.remove':
        if (service == null) return;
        final playlistId = data['playlistId']?.toString() ?? '';
        final songId = data['songId']?.toString() ?? '';
        if (playlistId.isNotEmpty) {
          await service.removeSongFromPlaylist(playlistId, songId);
        }
      case 'playlist_item.move':
        if (service == null) return;
        final playlistId = data['playlistId']?.toString() ?? '';
        final songId = data['songId']?.toString() ?? '';
        final target = (data['index'] as num?)?.toInt();
        final playlist = service.getPlaylist(playlistId);
        if (playlist != null && target != null) {
          final old = playlist.songs.indexWhere(
            (song) => song.identityKey == songId,
          );
          if (old >= 0) {
            await service.sortSongsInPlaylist(
              playlistId,
              oldIndex: old,
              newIndex: target,
            );
          }
        }
      case 'rating.set':
        final rating = (data['rating'] as num?)?.toInt();
        if (rating != null && _ratings != null) {
          await _ratings!.applyRemote(entityId, rating);
        }
      case 'rating.remove':
        if (_ratings != null) await _ratings!.applyRemoteRemove(entityId);
      case 'setting.set':
        final value = data['value']?.toString();
        if (value != null) await _settingApplier!(entityId, value);
      case 'custom_source.upsert':
        final raw = data['source'];
        if (raw is Map) {
          final source = CustomSource.fromJson(Map<String, dynamic>.from(raw));
          // 启用状态是设备本地偏好：同步只同步"源定义"。
          // - 本地已有同 id 源：保留本地启用状态（避免远端 isEnabled
          //   默认值把本地已禁用的源重新启用，也避免"三个源同时启用"）；
          // - 本地没有该源：默认禁用，由用户显式启用。
          final merged = [
            for (final existing in _sources!.sources)
              if (existing.id == source.id)
                source.copyWith(isEnabled: existing.isEnabled)
              else
                existing,
            if (!_sources!.sources.any((item) => item.id == source.id))
              source.copyWith(isEnabled: false),
          ];
          // Preserve the server timestamp exactly. updateSource() intentionally
          // stamps DateTime.now() for user edits and would cause devices to
          // endlessly echo the same source as a new event.
          await _sources!.replaceAllSources(merged);
        }
      case 'custom_source.remove':
        await _sources!.deleteSource(entityId);
    }
  }

  MusicItem? _song(dynamic raw) {
    if (raw is! Map) return null;
    try {
      return MusicItem.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }
}
