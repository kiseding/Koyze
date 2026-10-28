// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import '../../custom_source/domain/custom_source.dart';
import '../../download/domain/download_task.dart';
import '../../player/domain/music_item.dart';
import '../../playlist/domain/playlist.dart';
import '../../source_check/domain/source_check_report.dart';

/// AI 能执行的操作用到的后台接口。
///
/// 这一层的边界很明确：只有「人能做的操作」，并且只声明服务调用——不出现
/// Widget、路由、SnackBar。模型是在调服务，不是在点界面。真实实现在
/// `presentation/ai_ports.dart` 里包住现有服务，测试里换成假实现。
abstract interface class AiPlaybackPort {
  bool get isPlaying;
  MusicItem? get currentSong;
  Duration get position;
  double get volume;

  /// `off` / `all` / `one`，和界面上的三种循环模式一一对应。
  String get repeatMode;
  bool get shuffleEnabled;
  List<MusicItem> get queue;

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);

  /// 0..1。
  Future<void> setVolume(double volume);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeat(String mode);

  /// 用一批歌替换队列并从 [index] 开始播。
  Future<void> playSongs(List<MusicItem> songs, {int index = 0});

  /// 播放已保存的歌单（大歌单按需分页，不一次性全转换成原生队列）。
  Future<void> playPlaylist(String playlistId, {int index = 0});

  /// 插入队列。[playNext] 为真时插到当前歌曲后面，否则追加到队尾。
  Future<void> enqueue(List<MusicItem> songs, {bool playNext = false});

  /// 是否被标记为「不感兴趣」。
  Future<bool> isDisliked(MusicItem song);

  /// 标记 / 取消标记「不感兴趣」。标记过的歌在自动播放时会被跳过。
  Future<void> setDisliked(MusicItem song, bool disliked);

  /// 睡眠定时：传 null 取消。
  Future<void> setSleepTimer(Duration? duration);

  /// 距离睡眠定时触发还剩多久；没有开启时为 null。
  Duration? get sleepTimerRemaining;
}

enum AiPlaylistSortBy { name, artist, duration }

abstract interface class AiPlaylistPort {
  Future<List<Playlist>> loadPlaylists();

  /// 按 id 精确匹配，其次按名称精确匹配，最后按名称包含匹配。
  Future<Playlist?> findPlaylist(String query);

  Future<List<MusicItem>> songsOf(String playlistId);
  Future<Playlist> create({
    required String name,
    String? description,
    List<MusicItem> songs = const [],
  });
  Future<Playlist> update({
    required String id,
    String? name,
    String? description,
  });

  /// 系统歌单（收藏 / 最近播放 / 本地音乐）由实现方拒绝删除。
  Future<void> delete(String id);
  Future<int> addSongs(String playlistId, List<MusicItem> songs);
  Future<int> removeSongs(String playlistId, Iterable<String> tokens);
  Future<bool> sort(
    String playlistId,
    AiPlaylistSortBy by, {
    bool ascending = true,
  });
  Future<bool> setFavorite(MusicItem song, bool favorite);
  Future<bool> isFavorite(MusicItem song);
}

abstract interface class AiDownloadPort {
  List<DownloadTask> get tasks;
  Future<void> add(List<MusicItem> songs);
  Future<void> remove(String taskId);
  Future<void> clearCache();
}

abstract interface class AiSourcePort {
  List<CustomSource> get sources;
  SourceCheckBook get checkBook;

  /// 切换单个脚本的启用状态，返回切换后的状态。
  Future<bool> toggle(String id);

  /// 跑一次音源检测。[sourceId] 为空时检测全部已导入脚本。
  Future<void> runCheck(String? sourceId);
}

/// 界面设置里人手动改的那几项。
abstract interface class AiSettingsPort {
  String get audioQuality;
  String get downloadQuality;
  bool get wifiOnlyDownload;
  String get themeMode;

  Future<void> setAudioQuality(String token);
  Future<void> setDownloadQuality(String token);
  Future<void> setWifiOnlyDownload(bool value);
  Future<void> setThemeMode(String mode);
}
