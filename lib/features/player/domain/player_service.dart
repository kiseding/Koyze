import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import '../domain/music_item.dart';
import '../../../core/audio/audio_handler.dart';
import '../../../core/network/outbound_url.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_disk_cache.dart';
import 'lazy_playlist_order.dart';

class PlayerService {
  PlayerService({ArtworkDiskCache? artworkCache})
    : _artworkCache = artworkCache ?? ArtworkDiskCache.instance;

  final ArtworkDiskCache _artworkCache;
  int _queueGeneration = 0;

  int beginQueueReplacement() => ++_queueGeneration;

  bool ownsQueueReplacement(int generation) => generation == _queueGeneration;

  /// 当前惰性分页歌单 ID；播放列表弹窗据此展示完整分页列表。
  String? currentLazyPlaylistId;

  /// 当前惰性分页歌单的总歌曲数。
  int currentLazyPlaylistSongCount = 0;

  /// 正在播放的榜单 ID（排行榜页播放时设置，其他播放入口清零），
  /// 用于榜单行"正在播放"高亮。
  String? nowPlayingLeaderboardId;

  PlaybackState get playbackState => audioHandler.playbackState.value;
  bool get isPlaying => audioHandler.playbackState.value.playing;
  MediaItem? get mediaItem => audioHandler.mediaItem.value;

  Future<void> setQueue(
    List<MusicItem> songs, {
    int startIndex = 0,
    String? manualPlayName,
  }) async {
    await playPlaylist(
      songs,
      index: startIndex,
      manualPlayName: manualPlayName,
    );
  }

  /// Instant start: no await on artwork download.
  /// [manualPlayName] 非空时立即弹顶部通知（仅手动点击歌曲播放的场景，
  /// 自动切歌 / 会话恢复不传，避免误弹）。
  Future<void> playPlaylist(
    List<MusicItem> songs, {
    int index = 0,
    bool autoplay = true,
    bool userInitiated = true,
    String? manualPlayName,
    int? queueGeneration,
  }) async {
    final generation = queueGeneration ?? beginQueueReplacement();
    if (!ownsQueueReplacement(generation)) return;
    if (manualPlayName != null) {
      _notifyManualPlay(manualPlayName);
    }
    currentLazyPlaylistId = null;
    currentLazyPlaylistSongCount = 0;
    nowPlayingLeaderboardId = null;
    final items = songs.map(_convertToMediaItemSync).toList();
    if (audioHandler is LxAudioHandler) {
      final handler = audioHandler as LxAudioHandler;
      handler.clearLazyQueue();
      await handler.setPlaylist(
        items,
        initialIndex: index,
        playWhenReady: autoplay,
        userInitiated: userInitiated,
      );
      if (!ownsQueueReplacement(generation)) return;
      unawaited(
        _warmArtForQueue(
          songs,
          preferIndex: index,
          queueGeneration: generation,
        ),
      );
    }
  }

  /// Starts a large playlist without converting every saved song into a native
  /// media queue. The shuffled order covers every global index exactly once.
  Future<void> playPagedPlaylist({
    required int songCount,
    required int startIndex,
    required Future<List<MusicItem>> Function(int offset, int limit) loadPage,
    String? playlistId,
    bool autoplay = true,
    bool userInitiated = true,
    bool manual = false,
    int? queueGeneration,
  }) async {
    final generation = queueGeneration ?? beginQueueReplacement();
    if (!ownsQueueReplacement(generation)) return;
    currentLazyPlaylistId = playlistId;
    currentLazyPlaylistSongCount = songCount;
    nowPlayingLeaderboardId = null;
    if (songCount <= 0 || audioHandler is! LxAudioHandler) return;
    final handler = audioHandler as LxAudioHandler;
    final shuffle =
        handler.playbackState.value.shuffleMode == AudioServiceShuffleMode.all;
    var shuffleEnabled = shuffle;
    final window = LazyPlaylistWindow(
      length: songCount,
      initialIndex: startIndex,
      shuffle: shuffle,
      loadPage: loadPage,
    );

    List<MediaItem> mediaItems(List<LazyPlaylistEntry> entries) => [
      for (final entry in entries)
        _convertToMediaItemSync(entry.song, lazyPlaylistIndex: entry.index),
    ];

    final initialEntries = await window.takeEntries(9);
    if (!ownsQueueReplacement(generation) || initialEntries.isEmpty) return;
    if (manual) {
      _notifyManualPlay(initialEntries.first.song.name);
    }
    handler.configureLazyQueue(
      loadMore: (minimumItems) async {
        if (!ownsQueueReplacement(generation)) return const [];
        var entries = await window.takeEntries(minimumItems);
        if (!ownsQueueReplacement(generation)) return const [];
        if (entries.isEmpty &&
            handler.playbackState.value.repeatMode !=
                AudioServiceRepeatMode.none &&
            handler.playbackState.value.repeatMode !=
                AudioServiceRepeatMode.one) {
          entries = await window.restartFromBeginning(
            shuffle: shuffleEnabled,
            count: minimumItems,
          );
          if (!ownsQueueReplacement(generation)) return const [];
        }
        return mediaItems(entries);
      },
      rebuildForShuffle: (current, enabled, minimumItems) async {
        if (!ownsQueueReplacement(generation)) return const [];
        shuffleEnabled = enabled;
        final index = current.extras?['_lazyPlaylistIndex'];
        if (index is! int) return const [];
        final entries = await window.restartEntriesAfterCurrent(
          currentIndex: index,
          shuffle: enabled,
          count: minimumItems,
        );
        return ownsQueueReplacement(generation)
            ? mediaItems(entries)
            : const [];
      },
    );
    if (!ownsQueueReplacement(generation)) return;
    await handler.setPlaylist(
      mediaItems(initialEntries),
      playWhenReady: autoplay,
      userInitiated: userInitiated,
    );
    if (!ownsQueueReplacement(generation)) return;
    unawaited(
      _warmArtForQueue(
        initialEntries.map((entry) => entry.song).toList(growable: false),
        preferIndex: 0,
        queueGeneration: generation,
      ),
    );
  }

  Future<void> togglePlay() async {
    unawaited(HapticFeedback.selectionClick());
    if (audioHandler is LxAudioHandler) {
      final handler = audioHandler as LxAudioHandler;
      handler.player.playing ? await handler.pause() : await handler.play();
    } else {
      isPlaying ? await audioHandler.pause() : await audioHandler.play();
    }
  }

  void _notifyManualPlay(String songName) {
    showAppNotification('播放"$songName"', type: AppNotificationType.info);
  }

  MediaItem _convertToMediaItemSync(MusicItem song, {int? lazyPlaylistIndex}) {
    final art = song.artwork;
    return MediaItem(
      id: song.identityKey,
      album: song.album,
      title: song.name,
      artist: song.singer,
      duration: song.duration,
      artUri: (art != null && art.isNotEmpty)
          ? Uri.tryParse(normalizeOutboundUrl(art))
          : null,
      extras: {
        ...song.toJson(),
        if (lazyPlaylistIndex != null) '_lazyPlaylistIndex': lazyPlaylistIndex,
      },
    );
  }

  /// Download covers in background; patch file:// artUri for lock screen.
  Future<void> _warmArtForQueue(
    List<MusicItem> songs, {
    required int preferIndex,
    required int queueGeneration,
  }) async {
    if (!ownsQueueReplacement(queueGeneration) ||
        songs.isEmpty ||
        audioHandler is! LxAudioHandler) {
      return;
    }
    final handler = audioHandler as LxAudioHandler;
    final order = <int>[];
    void add(int i) {
      if (i >= 0 && i < songs.length && !order.contains(i)) order.add(i);
    }

    add(preferIndex);
    add(preferIndex + 1);
    add(preferIndex - 1);
    for (final i in order) {
      final song = songs[i];
      final remote = song.artwork;
      if (remote == null || remote.isEmpty) continue;
      try {
        final local = await _artworkCache.localArtUri(remote);
        if (!ownsQueueReplacement(queueGeneration)) return;
        if (local == null || local.scheme != 'file') continue;
        if (audioHandler is! LxAudioHandler) return;
        handler.patchQueueArtUri(song.identityKey, local);
      } catch (_) {}
    }
  }

  List<MediaItem> get queue {
    if (audioHandler is! LxAudioHandler) return const [];
    return (audioHandler as LxAudioHandler).queueItems;
  }

  int get currentIndex {
    if (audioHandler is! LxAudioHandler) return -1;
    return (audioHandler as LxAudioHandler).currentQueueIndex;
  }

  Future<void> playNext(MusicItem song) async {
    final item = _convertToMediaItemSync(song);
    if (audioHandler is LxAudioHandler) {
      final handler = audioHandler as LxAudioHandler;
      final items = List<MediaItem>.from(handler.queueItems);
      if (items.isEmpty) {
        final generation = beginQueueReplacement();
        handler.clearLazyQueue();
        await handler.setPlaylist([item], userInitiated: true);
        if (!ownsQueueReplacement(generation)) return;
        unawaited(
          _warmArtForQueue([song], preferIndex: 0, queueGeneration: generation),
        );
        return;
      }
      final currentId = handler.mediaItem.value?.id;
      items.removeWhere(
        (queueItem) =>
            _mediaIdentity(queueItem) == song.identityKey ||
            queueItem.id == song.id,
      );
      final currentIndex = items.indexWhere(
        (queueItem) => queueItem.id == currentId,
      );
      final insertIndex = (currentIndex + 1).clamp(0, items.length);
      items.insert(insertIndex, item);
      await handler.updateQueue(items);
      final generation = _queueGeneration;
      unawaited(
        _warmArtForQueue([song], preferIndex: 0, queueGeneration: generation),
      );
    }
  }

  String _mediaIdentity(MediaItem item) {
    final extras = item.extras;
    if (extras == null) return item.id;
    try {
      return MusicItem.fromJson(extras).identityKey;
    } catch (_) {
      return item.id;
    }
  }

  Future<void> next() {
    unawaited(HapticFeedback.selectionClick());
    return audioHandler.skipToNext();
  }

  Future<void> previous() {
    unawaited(HapticFeedback.selectionClick());
    return audioHandler.skipToPrevious();
  }

  Future<void> seek(Duration position) => audioHandler.seek(position);
  Future<void> stop() => audioHandler.stop();

  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await audioHandler.setRepeatMode(repeatMode);
  }

  Future<void> setShuffleMode(bool enabled) async {
    await audioHandler.setShuffleMode(
      enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }
}
