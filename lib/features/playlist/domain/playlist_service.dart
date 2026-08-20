import 'dart:async';

import '../../player/domain/music_item.dart';
import '../data/playlist_repository.dart';
import 'playlist.dart';

typedef PlaylistSyncRecorder =
    Future<void> Function({
      required String eventType,
      required String entityId,
      required Map<String, dynamic> payload,
    });

class PlaylistService {
  PlaylistService({
    required PlaylistRepository repository,
    DateTime Function()? clock,
    String Function()? createId,
    PlaylistSyncRecorder? syncRecorder,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now,
       _createId =
           createId ?? (() => DateTime.now().microsecondsSinceEpoch.toString()),
       _syncRecorder = syncRecorder;

  final PlaylistRepository _repository;
  final DateTime Function() _clock;
  final String Function() _createId;
  final PlaylistSyncRecorder? _syncRecorder;
  final List<Playlist> _playlists = [];
  final StreamController<int> _revisionController =
      StreamController<int>.broadcast();
  final StreamController<int> _pageRevisionController =
      StreamController<int>.broadcast();
  final StreamController<int> _recentRevisionController =
      StreamController<int>.broadcast();
  final StreamController<int> _syncRevisionController =
      StreamController<int>.broadcast();

  Future<void> _tail = Future.value();
  Future<void>? _initFuture;
  Future<void>? _disposeFuture;
  bool _initialized = false;
  bool _disposing = false;
  bool _suppressSyncRecording = false;
  int _revision = 0;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  int get revision => _revision;
  Stream<int> get revisions => _revisionController.stream;
  Stream<int> get pageRevisions => _pageRevisionController.stream;
  Stream<int> get recentRevisions => _recentRevisionController.stream;
  Stream<int> get syncRevisions => _syncRevisionController.stream;

  Future<List<Playlist>> getAllPlaylists() => _hydrateAll(_playlists);

  Future<List<PlaylistSongMatch>> searchSongs(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final matches = <({PlaylistSongMatch match, int score, int order})>[];
    var order = 0;
    for (final playlist in await getAllPlaylists()) {
      for (var index = 0; index < playlist.songs.length; index++) {
        final song = playlist.songs[index];
        final title = song.name.toLowerCase();
        final singer = song.singer.toLowerCase();
        final album = song.album.toLowerCase();
        final score = title.contains(normalized)
            ? (title == normalized ? 4 : 3)
            : singer.contains(normalized)
            ? 2
            : album.contains(normalized)
            ? 1
            : 0;
        if (score > 0) {
          matches.add((
            match: PlaylistSongMatch(
              playlist: playlist,
              song: song,
              index: index,
            ),
            score: score,
            order: order,
          ));
        }
        order++;
      }
    }
    matches.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score == 0 ? a.order.compareTo(b.order) : score;
    });
    return List.unmodifiable(matches.map((entry) => entry.match));
  }

  Future<void> init() {
    if (_disposing) {
      return Future.error(StateError('PlaylistService is disposed'));
    }
    if (_initialized) return Future.value();
    return _initFuture ??= _startInitialize().whenComplete(() {
      if (!_initialized) _initFuture = null;
    });
  }

  Future<void> _startInitialize() {
    final load = _repository.load();
    return _enqueue(() => _initialize(load));
  }

  Future<void> _initialize(Future<PlaylistSnapshot> load) async {
    final loaded = await load;
    _validatePlaylistIds(loaded.playlists, loadedState: true);
    final repaired = _withSystemPlaylists(loaded.playlists);
    _validatePlaylistIds(repaired, loadedState: true);
    final needsRepair = !_samePlaylists(loaded.playlists, repaired);
    if (needsRepair) {
      await _repository.save(
        PlaylistSnapshot(
          schemaVersion: 1,
          playlists: await _hydrateAll(repaired),
        ),
      );
    }
    _playlists
      ..clear()
      ..addAll(repaired);
    if (needsRepair) _revisionController.add(++_revision);
    _initialized = true;
  }

  Future<Playlist> createPlaylist({
    required String name,
    String? description,
    List<MusicItem> songs = const [],
    String? id,
  }) async {
    final result = await _mutate((current) {
      final createdId = id ?? _createId();
      _validateNewPlaylistId(createdId, current);
      final now = _clock();
      final created = Playlist(
        id: createdId,
        name: name,
        description: description,
        songs: List.unmodifiable(songs),
        createdAt: now,
        updatedAt: now,
      );
      return (next: [...current, created], result: created, changed: true);
    });
    await _recordSync(
      eventType: 'playlist.create',
      entityId: result.id,
      payload: {'name': result.name, 'description': result.description},
    );
    return result;
  }

  Future<Playlist> updatePlaylist({
    required String id,
    String? name,
    String? description,
    String? coverUrl,
    List<MusicItem>? songs,
  }) async {
    final result = await _mutate((current) {
      final index = _indexOf(current, id);
      final existing = current[index];
      final changed =
          (name != null && name != existing.name) ||
          (description != null && description != existing.description) ||
          (coverUrl != null && coverUrl != existing.coverUrl) ||
          (songs != null && !_sameSongs(songs, existing.songs));
      if (!changed) {
        return (next: current, result: existing, changed: false);
      }

      final updated = existing.copyWith(
        name: name,
        description: description,
        coverUrl: coverUrl,
        songs: songs == null ? null : List.unmodifiable(songs),
        updatedAt: _clock(),
      );
      final next = _replacePlaylistAt(current, index, updated);
      return (next: next, result: updated, changed: true);
    });
    if (name != null || description != null || coverUrl != null) {
      await _recordSync(
        eventType: 'playlist.rename',
        entityId: id,
        payload: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (coverUrl != null) 'coverUrl': coverUrl,
        },
      );
    }
    return result;
  }

  Future<bool> deletePlaylist(String id) async {
    if (_isSystemPlaylist(id)) {
      return Future.error(StateError('System playlists cannot be deleted'));
    }
    final removed = await _mutate((current) {
      final index = current.indexWhere((playlist) => playlist.id == id);
      if (index < 0) return (next: current, result: false, changed: false);
      final next = [...current]..removeAt(index);
      return (next: next, result: true, changed: true);
    });
    if (removed) {
      await _recordSync(
        eventType: 'playlist.delete',
        entityId: id,
        payload: const {},
      );
    }
    return removed;
  }

  Playlist? getPlaylist(String id) {
    final index = _playlists.indexWhere((playlist) => playlist.id == id);
    return index < 0 ? null : _playlists[index];
  }

  Future<PlaylistSongPage> getSongsPage(
    String playlistId, {
    required int offset,
    required int limit,
  }) async {
    if (offset < 0 || limit <= 0) {
      throw ArgumentError(
        'offset must be non-negative and limit must be positive',
      );
    }
    final playlist = getPlaylist(playlistId);
    if (playlist == null)
      throw StateError('Playlist $playlistId does not exist');
    if (playlist.songs.length == playlist.songCount) {
      final start = offset.clamp(0, playlist.songCount).toInt();
      final end = (start + limit).clamp(0, playlist.songCount).toInt();
      return PlaylistSongPage(
        total: playlist.songCount,
        offset: start,
        songs: playlist.songs.sublist(start, end),
      );
    }

    final repository = _repository;
    if (repository is PlaylistSongPageRepository) {
      final paged = repository as PlaylistSongPageRepository;
      return paged.loadSongsPage(playlistId, offset: offset, limit: limit);
    }
    throw StateError(
      'Playlist $playlistId does not support paged song loading',
    );
  }

  Future<List<MusicItem>> getAllSongs(String playlistId) async {
    final playlist = getPlaylist(playlistId);
    if (playlist == null)
      throw StateError('Playlist $playlistId does not exist');
    return _loadAllSongsFor(playlist);
  }

  Future<List<MusicItem>> _loadAllSongsFor(Playlist playlist) async {
    if (playlist.songs.length == playlist.songCount) return playlist.songs;

    final repository = _repository;
    if (repository is PlaylistSongPageRepository) {
      final paged = repository as PlaylistSongPageRepository;
      return paged.loadAllSongs(playlist.id);
    }
    throw StateError('Playlist ${playlist.id} does not support song loading');
  }

  Future<bool> addSongToPlaylist(
    String playlistId,
    MusicItem song, {
    String? playlistItemId,
  }) async {
    final added = await _mutate((current) {
      final index = _indexOf(current, playlistId);
      final existing = current[index];
      if (existing.songs.any((item) => item.identityKey == song.identityKey)) {
        return (next: current, result: false, changed: false);
      }
      final updated = existing.copyWith(
        songs: List.unmodifiable(
          playlistId == 'favorites'
              ? [
                  song.copyWith(playlistItemId: playlistItemId ?? _createId()),
                  ...existing.songs,
                ]
              : [
                  ...existing.songs,
                  song.copyWith(playlistItemId: playlistItemId ?? _createId()),
                ],
        ),
        updatedAt: _clock(),
      );
      final next = _replacePlaylistAt(current, index, updated);
      return (next: next, result: true, changed: true);
    });
    if (added && playlistId != 'recent' && playlistId != 'local') {
      final stored = (await getAllSongs(playlistId))
          .cast<MusicItem?>()
          .firstWhere(
            (item) => item?.identityKey == song.identityKey,
            orElse: () => null,
          );
      if (stored == null) return added;
      await _recordSync(
        eventType: playlistId == 'favorites'
            ? 'favorite.add'
            : 'playlist_item.add',
        entityId: playlistId == 'favorites'
            ? song.identityKey
            : stored.playlistItemId ?? '$playlistId:${song.identityKey}',
        payload: {'playlistId': playlistId, 'song': stored.toJson()},
      );
    }
    return added;
  }

  Future<bool> removeSongFromPlaylist(String playlistId, String songId) {
    return removeSongsFromPlaylist(playlistId, [songId]).then((n) => n > 0);
  }

  Future<bool> removeSongOccurrence(String playlistId, int index) {
    return _mutate((current) {
      final playlistIndex = _indexOf(current, playlistId);
      final existing = current[playlistIndex];
      RangeError.checkValidIndex(index, existing.songs, 'index');
      final songs = [...existing.songs]..removeAt(index);
      final updated = existing.copyWith(
        songs: List.unmodifiable(songs),
        updatedAt: _clock(),
      );
      return (
        next: _replacePlaylistAt(current, playlistIndex, updated),
        result: true,
        changed: true,
      );
    });
  }

  /// 批量移除同一歌单中的多首歌曲，只触发一次持久化与一次 revision，
  /// 避免逐首移除导致的重复刷新（UI 闪烁）。
  Future<int> removeSongsFromPlaylist(
    String playlistId,
    Iterable<String> songIds,
  ) async {
    final requestedIds = songIds.toSet();
    final removedSongDetails = <String, MusicItem>{};
    final removed = await _mutate((current) {
      final index = _indexOf(current, playlistId);
      final existing = current[index];
      if (existing.songs.isEmpty || requestedIds.isEmpty) {
        return (next: current, result: 0, changed: false);
      }
      final rawIdCounts = <String, int>{};
      for (final song in existing.songs) {
        rawIdCounts.update(song.id, (count) => count + 1, ifAbsent: () => 1);
      }
      var removed = 0;
      final kept = <MusicItem>[];
      for (final song in existing.songs) {
        final matchesItem = requestedIds.contains(song.playlistItemId);
        final matchesCanonical = requestedIds.contains(song.identityKey);
        final matchesUniqueLegacyId =
            requestedIds.contains(song.id) && rawIdCounts[song.id] == 1;
        if (matchesItem || matchesCanonical || matchesUniqueLegacyId) {
          removed++;
          removedSongDetails[song.identityKey] = song;
        } else {
          kept.add(song);
        }
      }
      if (removed == 0) {
        return (next: current, result: 0, changed: false);
      }
      final updated = existing.copyWith(
        songs: List.unmodifiable(kept),
        updatedAt: _clock(),
      );
      final next = _replacePlaylistAt(current, index, updated);
      return (next: next, result: removed, changed: true);
    });
    if (removed > 0 && playlistId != 'recent' && playlistId != 'local') {
      for (final songId in requestedIds) {
        final song = removedSongDetails[songId];
        await _recordSync(
          eventType: playlistId == 'favorites'
              ? 'favorite.remove'
              : 'playlist_item.remove',
          entityId: playlistId == 'favorites'
              ? songId
              : '$playlistId:${removedSongDetails[songId]?.playlistItemId ?? songId}',
          payload: {
            'playlistId': playlistId,
            'songId': songId,
            if (song != null) ...{
              'source': song.source,
              'songmid': song.songmid ?? song.id,
            },
          },
        );
      }
    }
    return removed;
  }

  Future<bool> isSongInPlaylist(String playlistId, String songId) async {
    final songs = await getAllSongs(playlistId);
    if (songs.any((song) => song.identityKey == songId)) return true;
    return songs.where((song) => song.id == songId).length == 1;
  }

  Future<bool> sortSongsInPlaylist(
    String playlistId, {
    required int oldIndex,
    required int newIndex,
  }) async {
    final moved = await _mutate((current) {
      final index = _indexOf(current, playlistId);
      final existing = current[index];
      final songs = [...existing.songs];
      RangeError.checkValidIndex(oldIndex, songs, 'oldIndex');
      RangeError.checkValueInInterval(newIndex, 0, songs.length, 'newIndex');
      var destination = newIndex;
      if (oldIndex < destination) destination--;
      if (oldIndex == destination) {
        return (next: current, result: false, changed: false);
      }
      final item = songs.removeAt(oldIndex);
      songs.insert(destination, item);
      final updated = existing.copyWith(
        songs: List.unmodifiable(songs),
        updatedAt: _clock(),
      );
      final next = _replacePlaylistAt(current, index, updated);
      return (next: next, result: true, changed: true);
    });
    if (moved && playlistId != 'recent' && playlistId != 'local') {
      final playlist = getPlaylist(playlistId);
      if (playlist != null && newIndex < playlist.songs.length) {
        final song = playlist.songs[newIndex];
        await _recordSync(
          eventType: 'playlist_item.move',
          entityId: '$playlistId:${song.playlistItemId ?? song.identityKey}',
          payload: {
            'playlistId': playlistId,
            'songId': song.playlistItemId ?? song.identityKey,
            'songmid': song.songmid ?? song.id,
            'source': song.source,
            'index': newIndex,
          },
        );
      }
    }
    return moved;
  }

  Future<bool> sortSongsByName(String playlistId, {bool ascending = true}) {
    return _sortSongs(
      playlistId,
      (a, b) => a.name.compareTo(b.name),
      ascending,
    );
  }

  Future<bool> sortSongsByArtist(String playlistId, {bool ascending = true}) {
    return _sortSongs(
      playlistId,
      (a, b) => a.singer.compareTo(b.singer),
      ascending,
    );
  }

  Future<bool> sortSongsByDuration(String playlistId, {bool ascending = true}) {
    return _sortSongs(
      playlistId,
      (a, b) => a.duration.compareTo(b.duration),
      ascending,
    );
  }

  Future<bool> addToRecent(MusicItem song) {
    return _mutate((current) {
      final index = _indexOf(current, 'recent');
      final existing = current[index];
      final seenIds = <String>{};
      final songs = <MusicItem>[];
      for (final item in [song, ...existing.songs]) {
        if (seenIds.add(item.identityKey)) {
          final previous = existing.songs.cast<MusicItem?>().firstWhere(
            (existingSong) => existingSong?.identityKey == item.identityKey,
            orElse: () => null,
          );
          songs.add(
            item.artwork?.isNotEmpty == true || previous?.artwork == null
                ? item
                : item.copyWith(artwork: previous!.artwork),
          );
        }
        if (songs.length == 100) break;
      }
      if (_sameSongs(songs, existing.songs)) {
        return (next: current, result: false, changed: false);
      }
      final updated = existing.copyWith(
        songs: List.unmodifiable(songs),
        updatedAt: _clock(),
      );
      final next = _replacePlaylistAt(current, index, updated);
      return (next: next, result: true, changed: true);
    }, revisionScope: PlaylistMutationScope.recent);
  }

  Future<int> addAllSongsToFavorites(String playlistId) {
    return _mutate((current) {
      final source = current[_indexOf(current, playlistId)];
      final favoritesIndex = _indexOf(current, 'favorites');
      final favorites = current[favoritesIndex];
      final ids = favorites.songs.map((song) => song.identityKey).toSet();
      final additions = source.songs
          .where((song) => ids.add(song.identityKey))
          .toList();
      if (additions.isEmpty) {
        return (next: current, result: 0, changed: false);
      }
      final updated = favorites.copyWith(
        songs: List.unmodifiable([...additions, ...favorites.songs]),
        updatedAt: _clock(),
      );
      final next = _replacePlaylistAt(current, favoritesIndex, updated);
      return (next: next, result: additions.length, changed: true);
    });
  }

  /// 整体替换本地音乐歌单的歌曲（本地库扫描结果落库）。
  Future<bool> replaceLocalSongs(List<MusicItem> songs) {
    return _mutate((current) {
      final index = _indexOf(current, 'local');
      final existing = current[index];
      if (_sameSongs(existing.songs, songs)) {
        return (next: current, result: false, changed: false);
      }
      final updated = existing.copyWith(
        songs: List.unmodifiable(songs),
        updatedAt: _clock(),
      );
      final next = _replacePlaylistAt(current, index, updated);
      return (next: next, result: true, changed: true);
    }, revisionScope: PlaylistMutationScope.local);
  }

  Future<void> replaceAll(List<Playlist> playlists, {bool syncable = true}) {
    return _mutate<void>(
      (current) {
        _validatePlaylistIds(playlists);
        final repaired = _withSystemPlaylists(playlists);
        if (_samePlaylists(current, repaired)) {
          return (next: current, result: null, changed: false);
        }
        return (
          next: List<Playlist>.unmodifiable(repaired),
          result: null,
          changed: true,
        );
      },
      revisionScope: PlaylistMutationScope.all,
      notifySync: syncable,
    );
  }

  Future<T> withoutSyncRecording<T>(Future<T> Function() operation) async {
    final previous = _suppressSyncRecording;
    _suppressSyncRecording = true;
    try {
      return await operation();
    } finally {
      _suppressSyncRecording = previous;
    }
  }

  Future<void> clearSyncableData() async {
    final keep = _playlists
        .where((playlist) => playlist.id == 'recent' || playlist.id == 'local')
        .toList(growable: false);
    await replaceAll(keep, syncable: false);
  }

  Future<void> restoreSnapshot(PlaylistSnapshot snapshot) {
    return _enqueue(() async {
      if (_disposing || !_initialized) {
        throw StateError('PlaylistService is not available for restore');
      }
      _validatePlaylistIds(snapshot.playlists);
      final repaired = PlaylistSnapshot(
        schemaVersion: 1,
        playlists: await _hydrateAll(_withSystemPlaylists(snapshot.playlists)),
      );
      await _repository.save(repaired);
      final persisted = _repository is PlaylistSongPageRepository
          ? await _repository.load()
          : repaired;
      _playlists
        ..clear()
        ..addAll(persisted.playlists);
      _notifyRevisions(PlaylistMutationScope.all);
    });
  }

  Playlist? get favorites => getPlaylist('favorites');
  Playlist? get recent => getPlaylist('recent');
  Playlist? get local => getPlaylist('local');

  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _disposing = true;
    return _disposeFuture = _tail.then((_) {
      _revisionController.close();
      _pageRevisionController.close();
      _recentRevisionController.close();
      _syncRevisionController.close();
    });
  }

  List<Playlist> _replacePlaylistAt(
    List<Playlist> current,
    int index,
    Playlist replacement,
  ) => [...current]..[index] = replacement;

  Future<bool> _sortSongs(
    String playlistId,
    int Function(MusicItem, MusicItem) compare,
    bool ascending,
  ) {
    return _mutate((current) {
      final index = _indexOf(current, playlistId);
      final existing = current[index];
      final songs = [...existing.songs]
        ..sort((a, b) => ascending ? compare(a, b) : -compare(a, b));
      if (_sameSongs(songs, existing.songs)) {
        return (next: current, result: false, changed: false);
      }
      final updated = existing.copyWith(
        songs: List.unmodifiable(songs),
        updatedAt: _clock(),
      );
      final next = _replacePlaylistAt(current, index, updated);
      return (next: next, result: true, changed: true);
    });
  }

  Future<T> _mutate<T>(
    FutureOr<({List<Playlist> next, T result, bool changed})> Function(
      List<Playlist> current,
    )
    operation, {
    PlaylistMutationScope revisionScope = PlaylistMutationScope.all,
    bool notifySync = true,
  }) {
    if (_disposing) {
      return Future.error(StateError('PlaylistService is disposed'));
    }
    return _enqueue(() async {
      if (!_initialized) {
        throw StateError('PlaylistService is not initialized');
      }
      final current = await _hydrateAll(_playlists);
      final mutation = await operation(List<Playlist>.unmodifiable(current));
      if (!mutation.changed) return mutation.result;

      final snapshot = PlaylistSnapshot(
        schemaVersion: 1,
        playlists: _withSystemPlaylists(mutation.next),
      );
      await _repository.save(snapshot);
      final persisted = _repository is PlaylistSongPageRepository
          ? await _repository.load()
          : snapshot;
      _playlists
        ..clear()
        ..addAll(persisted.playlists);
      _notifyRevisions(revisionScope, notifySync: notifySync);
      return mutation.result;
    });
  }

  void _notifyRevisions(PlaylistMutationScope scope, {bool notifySync = true}) {
    _revisionController.add(++_revision);
    if (scope == PlaylistMutationScope.all) {
      _pageRevisionController.add(_revision);
      _recentRevisionController.add(_revision);
      if (notifySync) _syncRevisionController.add(_revision);
    } else if (scope == PlaylistMutationScope.recent) {
      _recentRevisionController.add(_revision);
    } else if (scope == PlaylistMutationScope.local) {
      _pageRevisionController.add(_revision);
    }
  }

  Future<List<Playlist>> _hydrateAll(List<Playlist> playlists) async {
    return [
      for (final playlist in playlists)
        if (playlist.songs.length == playlist.songCount)
          playlist
        else
          playlist.copyWith(songs: await _loadAllSongsFor(playlist)),
    ];
  }

  Future<T> _enqueue<T>(FutureOr<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _recordSync({
    required String eventType,
    required String entityId,
    required Map<String, dynamic> payload,
  }) async {
    final recorder = _syncRecorder;
    if (recorder == null || _suppressSyncRecording) return;
    try {
      await recorder(
        eventType: eventType,
        entityId: entityId,
        payload: payload,
      );
    } catch (_) {
      // Local-first mutations must not fail because the offline outbox is unavailable.
    }
  }

  List<Playlist> _withSystemPlaylists(List<Playlist> source) {
    final result = [
      for (final playlist in source)
        playlist.id == 'recent'
            ? playlist.copyWith(songs: playlist.songs.take(100).toList())
            : playlist,
    ];
    if (!result.any((playlist) => playlist.id == 'favorites')) {
      result.add(
        _systemPlaylist(id: 'favorites', name: '收藏列表', description: '收藏的歌曲'),
      );
    }
    if (!result.any((playlist) => playlist.id == 'recent')) {
      result.add(
        _systemPlaylist(id: 'recent', name: '最近播放', description: '最近播放的歌曲'),
      );
    }
    if (!result.any((playlist) => playlist.id == 'local')) {
      result.add(
        _systemPlaylist(id: 'local', name: '本地音乐', description: '设备上的本地歌曲'),
      );
    }
    return List.unmodifiable(result);
  }

  Playlist _systemPlaylist({
    required String id,
    required String name,
    required String description,
  }) {
    final now = _clock();
    return Playlist(
      id: id,
      name: name,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
  }

  int _indexOf(List<Playlist> playlists, String id) {
    final index = playlists.indexWhere((playlist) => playlist.id == id);
    if (index < 0) throw StateError('Playlist $id does not exist');
    return index;
  }

  bool _sameSongs(List<MusicItem> left, List<MusicItem> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameMusicItem(left[index], right[index])) return false;
    }
    return true;
  }

  bool _samePlaylists(List<Playlist> left, List<Playlist> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.name != b.name ||
          a.description != b.description ||
          a.coverUrl != b.coverUrl ||
          a.createdAt != b.createdAt ||
          a.updatedAt != b.updatedAt ||
          a.songCount != b.songCount ||
          !_sameSongs(a.songs, b.songs)) {
        return false;
      }
    }
    return true;
  }

  bool _sameMusicItem(MusicItem left, MusicItem right) {
    return left.id == right.id &&
        left.name == right.name &&
        left.singer == right.singer &&
        left.album == right.album &&
        left.duration == right.duration &&
        left.source == right.source &&
        left.platform == right.platform &&
        left.artwork == right.artwork &&
        left.url == right.url &&
        left.lyricsUrl == right.lyricsUrl &&
        left.isPlayable == right.isPlayable &&
        left.songmid == right.songmid &&
        left.hash == right.hash &&
        left.playlistItemId == right.playlistItemId &&
        _sameJson(left.meta, right.meta);
  }

  bool _sameJson(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final key in left.keys) {
        if (!right.containsKey(key) || !_sameJson(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_sameJson(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  void _validatePlaylistIds(
    List<Playlist> playlists, {
    bool loadedState = false,
  }) {
    final ids = <String>{};
    for (final playlist in playlists) {
      if (playlist.id.trim().isEmpty || !ids.add(playlist.id)) {
        if (loadedState) {
          throw StateError('Loaded playlist IDs must be unique and non-empty');
        }
        throw ArgumentError.value(
          playlist.id,
          'playlists',
          'Playlist IDs must be unique and non-empty',
        );
      }
    }
  }

  void _validateNewPlaylistId(String id, List<Playlist> current) {
    if (id.trim().isEmpty || current.any((playlist) => playlist.id == id)) {
      throw ArgumentError.value(
        id,
        'id',
        'Playlist ID must be unique and non-empty',
      );
    }
  }

  bool _isSystemPlaylist(String id) =>
      id == 'favorites' || id == 'recent' || id == 'local';
}

final class PlaylistSongMatch {
  const PlaylistSongMatch({
    required this.playlist,
    required this.song,
    required this.index,
  });

  final Playlist playlist;
  final MusicItem song;
  final int index;
}

enum PlaylistMutationScope { all, recent, local }
