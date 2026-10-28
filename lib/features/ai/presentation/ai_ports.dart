// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/music_source/platform/music_platform.dart';
import '../../custom_source/domain/custom_source.dart';
import '../../custom_source/presentation/custom_source_provider.dart';
import '../../download/domain/download_service.dart';
import '../../download/domain/download_task.dart';
import '../../download/presentation/download_provider.dart';
import '../../equalizer/domain/equalizer_preset.dart';
import '../../equalizer/domain/equalizer_settings.dart';
import '../../equalizer/presentation/equalizer_provider.dart';
import '../../leaderboard/presentation/leaderboard_provider.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../../lyric/presentation/lyric_provider.dart';
import '../../player/domain/music_item.dart';
import '../../player/domain/player_service.dart';
import '../../player/presentation/player_provider.dart';
import '../../playlist/domain/playlist.dart';
import '../../playlist/domain/playlist_service.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../recommend/domain/recommendation_engine.dart';
import '../../recommend/domain/recommendation_tuning.dart';
import '../../recommend/presentation/recommendation_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../stats/data/play_history_store.dart';
import '../../stats/presentation/play_history_provider.dart';
import '../../sync/presentation/sync_phase1_provider.dart';
import '../../source_check/domain/source_check_report.dart';
import '../../source_check/presentation/source_check_provider.dart';
import '../domain/ai_action_ports.dart';
import '../domain/ai_schedule.dart';
import 'ai_schedule_provider.dart';

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

/// 「猜你喜欢」：读当前结果、改调校、重算。
///
/// 重算是异步的（要联网补候选），所以 apply 会把重算后的结果直接返回，
/// 模型下一次工具调用就能看到自己改完的效果。
class ProviderAiRecommendationPort implements AiRecommendationPort {
  ProviderAiRecommendationPort(this._ref);

  final Ref _ref;

  @override
  List<RecommendedSong> get current =>
      _ref.read(recommendationProvider).valueOrNull ??
      const <RecommendedSong>[];

  @override
  bool get hasData => _ref.read(recommendationProvider).hasValue;

  @override
  RecommendationTuning get tuning => _ref.read(recommendationTuningProvider);

  @override
  Future<List<RecommendedSong>> apply(RecommendationTuning tuning) async {
    await _ref.read(recommendationTuningProvider.notifier).apply(tuning);
    return refresh();
  }

  @override
  Future<List<RecommendedSong>> refresh() async {
    await _ref.read(recommendationProvider.notifier).refresh();
    return current;
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

/// 均衡器：读当前状态、按频率改频段增益。
///
/// 平台不支持时 [supported] 为假；上层工具先看这一位，给出「这个平台上没有
/// 均衡器」而不是静默无效。
class ProviderAiEqualizerPort implements AiEqualizerPort {
  ProviderAiEqualizerPort(this._ref);

  final Ref _ref;

  EqualizerState get _state => _ref.read(equalizerProvider);
  EqualizerNotifier get _notifier => _ref.read(equalizerProvider.notifier);

  @override
  bool get supported => _state.supported;

  @override
  bool get enabled => _state.settings.enabled;

  @override
  String get presetId => _state.settings.presetId;

  @override
  List<({String id, String label})> get presets => [
    for (final preset in equalizerPresets) (id: preset.id, label: preset.label),
    (id: kCustomPresetId, label: '自定义'),
  ];

  @override
  List<AiEqualizerBand> get bands {
    final layout = _state.effectiveLayout;
    final gains = _state.settings.gainsFor(layout);
    return [
      for (var index = 0; index < layout.centerFrequencies.length; index++)
        AiEqualizerBand(
          frequencyHz: layout.centerFrequencies[index],
          gainDb: index < gains.length ? gains[index] : 0,
        ),
    ];
  }

  @override
  double get minDecibels => _state.effectiveLayout.minDecibels;

  @override
  double get maxDecibels => _state.effectiveLayout.maxDecibels;

  @override
  Future<void> setEnabled(bool enabled) => _notifier.setEnabled(enabled);

  @override
  Future<void> selectPreset(String presetId) =>
      _notifier.selectPreset(presetId);

  @override
  Future<bool> setBandGain(double frequencyHz, double gainDb) async {
    final layout = _state.effectiveLayout;
    final centers = layout.centerFrequencies;
    if (centers.isEmpty) return false;
    var best = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index < centers.length; index++) {
      final distance = (centers[index] - frequencyHz).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = index;
      }
    }
    // 频段按对数分布：60 与 230 只差 170，3600 与 14000 却差 10400。所以用
    // 倍频程判断是不是同一段，差出两个倍频以上就当模型给的频率对不上这台
    // 设备，宁可返回 false 让模型换一个，也不要悄悄改了隔壁频段。
    final target = centers[best];
    final ratio = frequencyHz <= 0 ? 1.0 : target / frequencyHz;
    if (ratio > 2 || ratio < 0.5) return false;
    final clamped = gainDb.clamp(layout.minDecibels, layout.maxDecibels);
    await _notifier.setBandGain(best, clamped.toDouble());
    return true;
  }

  @override
  Future<void> resetFlat() => _notifier.resetToFlat();
}

/// 听歌统计：直接读本地播放历史。
class ProviderAiStatsPort implements AiStatsPort {
  ProviderAiStatsPort(this._ref);

  final Ref _ref;

  @override
  AiStatsSnapshot snapshot(String range, {int limit = 10}) {
    final store = _ref.read(playHistoryStoreProvider);
    final statsRange = switch (range) {
      'month' => StatsRange.month,
      'year' => StatsRange.year,
      'all' => StatsRange.all,
      _ => StatsRange.week,
    };
    final entries = store.entriesIn(statsRange);
    final totalSeconds = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.listenedSec,
    );
    final activeDays = store
        .dailyPlayCounts(statsRange)
        .where((item) => item.$2 > 0)
        .length;
    return AiStatsSnapshot(
      range: range,
      playCount: entries.length,
      totalSeconds: totalSeconds.round(),
      activeDays: activeDays,
      songs: _ranked(store.topSongs(statsRange, limit: limit)),
      artists: _ranked(store.topArtists(statsRange, limit: limit)),
      albums: _ranked(store.topAlbums(statsRange, limit: limit)),
    );
  }

  static List<AiRankedEntry> _ranked(List<RankedItem> items) => [
    for (final item in items)
      AiRankedEntry(
        title: item.title,
        subtitle: item.subtitle,
        playCount: item.playCount,
        totalSeconds: item.totalSec.round(),
      ),
  ];
}

/// 歌词：走和歌词页同一个 `LyricService`，取不到就是 null。
class ProviderAiLyricPort implements AiLyricPort {
  ProviderAiLyricPort(this._ref);

  final Ref _ref;

  @override
  Future<List<AiLyricLine>?> lyricsOf(MusicItem song) async {
    final lyrics = await _ref.read(lyricServiceProvider).fetchLyric(song);
    if (lyrics.isEmpty) return null;
    return [
      for (final line in lyrics.lines)
        if (line.text.trim().isNotEmpty)
          AiLyricLine(seconds: line.time.inSeconds, text: line.text.trim()),
    ];
  }
}

/// 榜单：分类来自榜单页那份缓存，歌曲按 id 拉。
class ProviderAiChartPort implements AiChartPort {
  ProviderAiChartPort(this._ref);

  final Ref _ref;

  @override
  Future<List<AiChartEntry>> charts({String? platform}) async {
    // 榜单分类是 NotifierProvider<AsyncValue>，没有 `.future`：先取现值，
    // 还在加载就催一次刷新再取；仍然拿不到就返回空表，让模型知道「没有榜单」。
    var value = _ref.read(leaderboardCategoriesProvider).valueOrNull;
    if (value == null) {
      await _ref.read(leaderboardCategoriesProvider.notifier).refresh();
      value = _ref.read(leaderboardCategoriesProvider).valueOrNull;
    }
    final categories = value ?? const <LeaderboardCategory>[];
    return [
      for (final category in categories)
        if (platform == null ||
            category.platform == platform ||
            category.id.startsWith('$platform:'))
          AiChartEntry(
            id: category.id,
            name: category.name,
            platform: category.platform ?? category.id.split(':').first,
          ),
    ];
  }

  @override
  Future<List<MusicItem>> songsOf(String chartId) =>
      _ref.read(leaderboardSongsProvider(chartId).future);
}

/// AI 的定时任务：转发到定时任务列表与执行器。
class ProviderAiSchedulePort implements AiSchedulePort {
  ProviderAiSchedulePort(this._ref);

  final Ref _ref;

  AiSchedulesNotifier get _notifier => _ref.read(aiSchedulesProvider.notifier);

  @override
  List<AiScheduledTask> get tasks => _ref.read(aiSchedulesProvider);

  @override
  Future<AiScheduledTask?> create({
    required String title,
    required String prompt,
    required int minuteOfDay,
    required String cadence,
    int? weekday,
    bool enabled = true,
  }) async {
    AiScheduleCadence? parsed;
    for (final value in AiScheduleCadence.values) {
      if (value.name == cadence) parsed = value;
    }
    if (parsed == null) return null;
    final task = AiScheduledTask(
      id: AiSchedulesNotifier.newId(),
      title: title,
      prompt: prompt,
      minuteOfDay: minuteOfDay,
      cadence: parsed,
      weekday: (weekday ?? 1).clamp(1, 7),
      enabled: enabled,
    );
    await _notifier.add(task);
    return task;
  }

  @override
  Future<bool> setEnabled(String id, bool enabled) async {
    if (!tasks.any((task) => task.id == id)) return false;
    await _notifier.setEnabled(id, enabled);
    return true;
  }

  @override
  Future<bool> remove(String id) async {
    if (!tasks.any((task) => task.id == id)) return false;
    await _notifier.remove(id);
    return true;
  }

  @override
  Future<({bool ok, String summary})> runNow(String id) async {
    AiScheduledTask? task;
    for (final item in tasks) {
      if (item.id == id) task = item;
    }
    if (task == null) return (ok: false, summary: '没有这个任务');
    final result = await _ref.read(aiScheduleRunnerProvider).runNow(task);
    if (result.skipped) return (ok: false, summary: '正忙，稍后再试');
    if (!result.ok) {
      return (ok: false, summary: result.failure?.name ?? '执行失败');
    }
    return (ok: true, summary: result.text);
  }
}

/// 本地曲库：重新扫描用户选的目录（Android 上还有系统媒体库）。
class ProviderAiLocalPort implements AiLocalPort {
  ProviderAiLocalPort(this._ref);

  final Ref _ref;

  @override
  Future<int> rescan() async {
    final library = await _ref.read(localMusicLibraryProvider.future);
    return library.rescanAll();
  }
}
