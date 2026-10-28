// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import '../../custom_source/domain/custom_source.dart';
import '../../download/domain/download_task.dart';
import '../../player/domain/music_item.dart';
import '../../playlist/domain/playlist.dart';
import '../../recommend/domain/recommendation_engine.dart';
import '../../recommend/domain/recommendation_tuning.dart';
import '../../source_check/domain/source_check_report.dart';
import 'ai_schedule.dart';

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

/// 「猜你喜欢」的读取与调校。
///
/// 推荐结果由算法算，这里只做两件事：把当前结果读给模型看，以及按用户（或
/// 模型转述的）要求改调校再重算一次。
abstract interface class AiRecommendationPort {
  /// 当前缓存里的推荐结果；还没算出来时为空。
  List<RecommendedSong> get current;

  /// 是否已经有一份算好的结果（哪怕为空）。
  bool get hasData;

  RecommendationTuning get tuning;

  /// 落盘 + 重算。返回重算后的结果。
  Future<List<RecommendedSong>> apply(RecommendationTuning tuning);

  /// 按现有调校重算一遍。
  Future<List<RecommendedSong>> refresh();
}

/// 均衡器的一个频段。
class AiEqualizerBand {
  const AiEqualizerBand({required this.frequencyHz, required this.gainDb});

  final double frequencyHz;
  final double gainDb;
}

/// 均衡器：开关、预设与逐频段增益。
///
/// iOS / macOS / Windows 上没有可用实现，此时 [supported] 为假，写操作整体
/// 返回错误而不是假装成功——模型据此告诉用户「这个平台上没有均衡器」。
abstract interface class AiEqualizerPort {
  bool get supported;
  bool get enabled;

  /// 当前预设 id；手动拖过频段时是 `custom`。
  String get presetId;

  /// 预设清单：id 与展示名。
  List<({String id, String label})> get presets;

  /// 设备当前频段与已施加的增益（dB）。
  List<AiEqualizerBand> get bands;

  double get minDecibels;
  double get maxDecibels;

  Future<void> setEnabled(bool enabled);
  Future<void> selectPreset(String presetId);

  /// 按频率就近匹配一个频段后设增益。
  Future<bool> setBandGain(double frequencyHz, double gainDb);

  Future<void> resetFlat();
}

/// 统计榜单里的一行。
class AiRankedEntry {
  const AiRankedEntry({
    required this.title,
    required this.subtitle,
    required this.playCount,
    required this.totalSeconds,
  });

  final String title;
  final String subtitle;
  final int playCount;
  final int totalSeconds;
}

/// 一段时间范围内的听歌概况。
class AiStatsSnapshot {
  const AiStatsSnapshot({
    required this.range,
    required this.playCount,
    required this.totalSeconds,
    required this.activeDays,
    required this.songs,
    required this.artists,
    required this.albums,
  });

  final String range;
  final int playCount;
  final int totalSeconds;
  final int activeDays;
  final List<AiRankedEntry> songs;
  final List<AiRankedEntry> artists;
  final List<AiRankedEntry> albums;
}

/// 听歌统计（只读）。范围用 `week` / `month` / `year` / `all` 四个词。
abstract interface class AiStatsPort {
  /// 最近一次统计的时间点；没有播放记录时次数为 0。
  AiStatsSnapshot snapshot(String range, {int limit = 10});
}

/// 一行歌词。
class AiLyricLine {
  const AiLyricLine({required this.seconds, required this.text});

  final int seconds;
  final String text;
}

/// 歌词（只读）。取不到时返回 null，不做兜底编造。
abstract interface class AiLyricPort {
  Future<List<AiLyricLine>?> lyricsOf(MusicItem song);
}

/// 一个排行榜。
class AiChartEntry {
  const AiChartEntry({
    required this.id,
    required this.name,
    required this.platform,
  });

  /// `platform:id` 形式的复合 id，可以直接喂回 [AiChartPort.songsOf]。
  final String id;
  final String name;
  final String platform;
}

/// 排行榜（只读 + 播放由播放端口负责）。
abstract interface class AiChartPort {
  /// [platform] 为空时返回所有平台的榜单；否则按平台 id 过滤。
  Future<List<AiChartEntry>> charts({String? platform});

  Future<List<MusicItem>> songsOf(String chartId);
}

/// 本地曲库：只暴露「重新扫描」这一个动作。
///
/// 扫描会遍历用户选的目录（Android 上还包括系统媒体库），耗时不确定，所以工具
/// 描述里写明了可能较慢；返回值是这次新增的曲目数。
abstract interface class AiLocalPort {
  Future<int> rescan();
}

/// AI 的定时任务：列出、新建、暂停、删除、立即执行。
///
/// `cadence` 用 `daily` / `weekdays` / `weekly` 三个词，[weekday] 只在
/// `weekly` 时有意义（1 = 周一，7 = 周日）。
abstract interface class AiSchedulePort {
  List<AiScheduledTask> get tasks;

  Future<AiScheduledTask?> create({
    required String title,
    required String prompt,
    required int minuteOfDay,
    required String cadence,
    int? weekday,
    bool enabled = true,
  });

  Future<bool> setEnabled(String id, bool enabled);
  Future<bool> remove(String id);

  /// 立即跑一次，返回成功与否与一句话结果。
  Future<({bool ok, String summary})> runNow(String id);
}

