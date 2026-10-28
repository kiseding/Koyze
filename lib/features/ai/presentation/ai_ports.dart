// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../custom_source/domain/custom_source.dart';
import '../../custom_source/presentation/custom_source_provider.dart';
import '../../download/domain/download_service.dart';
import '../../download/domain/download_task.dart';
import '../../download/presentation/download_provider.dart';
import '../../player/domain/music_item.dart';
import '../../player/domain/player_service.dart';
import '../../player/presentation/player_provider.dart';
import '../../playlist/domain/playlist.dart';
import '../../playlist/domain/playlist_service.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/presentation/sync_phase1_provider.dart';
import '../../source_check/domain/source_check_report.dart';
import '../../source_check/presentation/source_check_provider.dart';
import '../domain/ai_action_ports.dart';

/// 把 AI 的操作端口接到真实服务上。
///
/// 这一层只做转发：不弹提示、不导航、不读界面状态，所以模型在哪个页面被唤起、
/// 甚至应用在后台，操作都照样生效，界面通过服务自己的变更通知跟着刷新。
class ProviderAiPlaybackPort implements AiPlaybackPort {
  ProviderAiPlaybackPort(this._ref);

  final Ref _ref;

  PlayerService get _player => _ref.read(playerServiceProvider);

  @override
  bool get isPlaying => _player.isPlaying;

  @override
  MusicItem? get currentSong => _songOf(_player.mediaItem);

  @override
  Duration get position => _ref.read(playerPositionProvider);

  @override
  double get volume => _ref.read(playbackVolumeProvider);

  @override
  bool get shuffleEnabled =>
      _player.playbackState.shuffleMode == AudioServiceShuffleMode.all;

  @override
  String get repeatMode => switch (_player.playbackState.repeatMode) {
    AudioServiceRepeatMode.all => 'all',
    AudioServiceRepeatMode.one => 'one',
    _ => 'off',
  };

  @override
  List<MusicItem> get queue => [
    for (final item in _player.queue)
      if (_songOf(item) case final song?) song,
  ];

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> next() => _player.next();

  @override
  Future<void> previous() => _player.previous();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) async {
    _ref.read(playbackVolumeProvider.notifier).setVolume(volume);
  }

  @override
  Future<void> setShuffle(bool enabled) => _player.setShuffleMode(enabled);

  @override
  Future<void> setRepeat(String mode) => _player.setRepeatMode(switch (mode) {
    'all' => AudioServiceRepeatMode.all,
    'one' => AudioServiceRepeatMode.one,
    _ => AudioServiceRepeatMode.none,
  });

  @override
  Future<void> playSongs(List<MusicItem> songs, {int index = 0}) {
    return _player.playPlaylist(songs, index: index, userInitiated: true);
  }

  @override
  Future<void> playPlaylist(String playlistId, {int index = 0}) async {
    final service = _ref.read(playlistServiceProvider);
    final playlist = service.getPlaylist(playlistId);
    if (playlist == null) {
      throw StateError('Playlist $playlistId does not exist');
    }
    await _player.playPagedPlaylist(
      songCount: playlist.songCount,
      startIndex: index,
      playlistId: playlistId,
      manual: true,
      loadPage: (offset, limit) async {
        final page = await service.getSongsPage(
          playlistId,
          offset: offset,
          limit: limit,
        );
        return page.songs;
      },
    );
  }

  @override
  Future<void> enqueue(List<MusicItem> songs, {bool playNext = false}) async {
    if (!playNext) {
      await _player.enqueueSongs(songs);
      return;
    }
    // 逐首插到「下一首」会让后插入的排在前面，倒着插才能保持给定顺序。
    for (final song in songs.reversed) {
      await _player.playNext(song);
    }
  }

  @override
  Future<bool> isDisliked(MusicItem song) async {
    final ratings = await _ref.read(ratingServiceProvider).store.load();
    return ratings[song.identityKey] == PlayerService.dislikedRating;
  }

  @override
  Future<void> setDisliked(MusicItem song, bool disliked) async {
    final service = _ref.read(ratingServiceProvider);
    if (disliked) {
      await service.set(song.identityKey, PlayerService.dislikedRating);
      return;
    }
    await service.remove(song.identityKey);
  }

  @override
  Future<void> setSleepTimer(Duration? duration) async {
    final notifier = _ref.read(sleepTimerProvider.notifier);
    if (duration == null) {
      notifier.cancelTimer();
      return;
    }
    notifier.startTimer(duration);
  }

  @override
  Duration? get sleepTimerRemaining {
    final state = _ref.read(sleepTimerProvider);
    final end = state.endTime;
    if (end == null) return null;
    final remaining = end.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static MusicItem? _songOf(MediaItem? item) {
    final extras = item?.extras;
    if (extras == null) return null;
    try {
      return MusicItem.fromJson(Map<String, dynamic>.from(extras));
    } catch (_) {
      return null;
    }
  }
}

class ProviderAiPlaylistPort implements AiPlaylistPort {
  ProviderAiPlaylistPort(this._ref);

  final Ref _ref;

  PlaylistService get _service => _ref.read(playlistServiceProvider);

  @override
  Future<List<Playlist>> loadPlaylists() => _service.getAllPlaylists();

  @override
  Future<Playlist?> findPlaylist(String query) async {
    final value = query.trim();
    if (value.isEmpty) return null;
    final all = await _service.getAllPlaylists();
    for (final playlist in all) {
      if (playlist.id == value) return playlist;
    }
    for (final playlist in all) {
      if (playlist.name == value) return playlist;
    }
    final lowered = value.toLowerCase();
    for (final playlist in all) {
      if (playlist.name.toLowerCase().contains(lowered)) return playlist;
    }
    return null;
  }

  @override
  Future<List<MusicItem>> songsOf(String playlistId) =>
      _service.getAllSongs(playlistId);

  @override
  Future<Playlist> create({
    required String name,
    String? description,
    List<MusicItem> songs = const [],
  }) => _service.createPlaylist(
    name: name,
    description: description,
    songs: songs,
  );

  @override
  Future<Playlist> update({
    required String id,
    String? name,
    String? description,
  }) => _service.updatePlaylist(id: id, name: name, description: description);

  @override
  Future<void> delete(String id) async {
    if (_systemPlaylists.contains(id)) {
      throw StateError('System playlists cannot be deleted');
    }
    await _service.deletePlaylist(id);
  }

  @override
  Future<int> addSongs(String playlistId, List<MusicItem> songs) async {
    var added = 0;
    for (final song in songs) {
      if (await _service.addSongToPlaylist(playlistId, song)) added++;
    }
    return added;
  }

  @override
  Future<int> removeSongs(String playlistId, Iterable<String> tokens) =>
      _service.removeSongsFromPlaylist(playlistId, tokens);

  @override
  Future<bool> sort(
    String playlistId,
    AiPlaylistSortBy by, {
    bool ascending = true,
  }) => switch (by) {
    AiPlaylistSortBy.name => _service.sortSongsByName(
      playlistId,
      ascending: ascending,
    ),
    AiPlaylistSortBy.artist => _service.sortSongsByArtist(
      playlistId,
      ascending: ascending,
    ),
    AiPlaylistSortBy.duration => _service.sortSongsByDuration(
      playlistId,
      ascending: ascending,
    ),
  };

  @override
  Future<bool> setFavorite(MusicItem song, bool favorite) async {
    final already = await isFavorite(song);
    if (already == favorite) return false;
    if (favorite) {
      await _service.addSongToPlaylist('favorites', song);
      return true;
    }
    final favorites = await _service.getAllSongs('favorites');
    for (final item in favorites) {
      if (item.isSameCatalogTrack(song)) {
        await _service.removeSongFromPlaylist('favorites', item.identityKey);
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> isFavorite(MusicItem song) async {
    final favorites = await _service.getAllSongs('favorites');
    return favorites.any((item) => item.isSameCatalogTrack(song));
  }

  static const Set<String> _systemPlaylists = {'favorites', 'recent', 'local'};
}

class ProviderAiDownloadPort implements AiDownloadPort {
  ProviderAiDownloadPort(this._ref);

  final Ref _ref;

  DownloadService get _service => _ref.read(downloadServiceProvider);

  @override
  List<DownloadTask> get tasks => _ref.read(downloadTasksProvider);

  @override
  Future<void> add(List<MusicItem> songs) async {
    final quality = audioQualityToken(_ref.read(downloadQualityProvider));
    for (final song in songs) {
      await _service.addTask(song, quality: quality);
    }
    _bump();
  }

  @override
  Future<void> remove(String taskId) async {
    await _service.deleteDownloaded(taskId);
    _bump();
  }

  @override
  Future<void> clearCache() async {
    await _service.clearCache();
    _bump();
  }

  void _bump() => _ref.read(downloadVersionProvider.notifier).state++;
}

class ProviderAiSourcePort implements AiSourcePort {
  ProviderAiSourcePort(this._ref);

  final Ref _ref;

  /// 服务层持有的脚本列表是唯一真源，状态 provider 只是它的投影。
  List<CustomSource> get _sources => _ref.read(customSourcesProvider);

  @override
  List<CustomSource> get sources => _sources;

  @override
  SourceCheckBook get checkBook =>
      _ref.read(sourceCheckControllerProvider).book;

  @override
  Future<bool> toggle(String id) =>
      _ref.read(customSourcesProvider.notifier).toggleSource(id);

  @override
  Future<void> runCheck(String? sourceId) async {
    final controller = _ref.read(sourceCheckControllerProvider.notifier);
    if (sourceId == null) {
      await controller.runAll(_sources);
      return;
    }
    for (final source in _sources) {
      if (source.id == sourceId) {
        await controller.runSource(source);
        return;
      }
    }
    throw StateError('Source $sourceId does not exist');
  }
}

class ProviderAiSettingsPort implements AiSettingsPort {
  ProviderAiSettingsPort(this._ref);

  final Ref _ref;

  @override
  String get audioQuality => _ref.read(audioQualityProvider).name;

  @override
  String get downloadQuality => _ref.read(downloadQualityProvider).name;

  @override
  bool get wifiOnlyDownload => _ref.read(wifiOnlyDownloadProvider);

  @override
  String get themeMode => _ref.read(themeModeProvider).name;

  @override
  Future<void> setAudioQuality(String token) => _ref
      .read(audioQualityProvider.notifier)
      .setQuality(AudioQualityOption.values.byName(token));

  @override
  Future<void> setDownloadQuality(String token) => _ref
      .read(downloadQualityProvider.notifier)
      .setQuality(AudioQualityOption.values.byName(token));

  @override
  Future<void> setWifiOnlyDownload(bool value) =>
      _ref.read(wifiOnlyDownloadProvider.notifier).setWifiOnly(value);

  @override
  Future<void> setThemeMode(String mode) => _ref
      .read(themeModeProvider.notifier)
      .setThemeMode(ThemeMode.values.byName(mode));
}
