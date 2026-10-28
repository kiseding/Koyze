import 'package:koyze/features/ai/domain/ai_action_ports.dart';
import 'package:koyze/features/ai/domain/ai_schedule.dart';
import 'package:koyze/features/ai/domain/ai_tools.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/download/domain/download_task.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/recommend/domain/recommendation_engine.dart';
import 'package:koyze/features/recommend/domain/recommendation_tuning.dart';
import 'package:koyze/features/source_check/domain/source_check_report.dart';

MusicItem song(
  String id,
  String name,
  String singer, {
  Duration duration = Duration.zero,
}) => MusicItem(
  id: id,
  name: name,
  singer: singer,
  duration: duration,
  source: 'src',
  platform: 'tx',
);

Playlist playlist(String id, String name, List<MusicItem> songs) => Playlist(
  id: id,
  name: name,
  songs: songs,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class FakePlayback implements AiPlaybackPort {
  FakePlayback({List<MusicItem>? queue}) : queue = [...?queue];

  @override
  bool isPlaying = false;

  @override
  MusicItem? currentSong;

  @override
  Duration position = Duration.zero;

  @override
  double volume = 1;

  @override
  String repeatMode = 'off';

  @override
  bool shuffleEnabled = false;

  @override
  List<MusicItem> queue;

  final List<String> calls = [];
  final List<MusicItem> played = [];
  final List<MusicItem> enqueued = [];
  final List<double> volumes = [];
  Duration? lastSeek;
  String? playedPlaylistId;
  int playedPlaylistIndex = 0;

  @override
  Future<void> play() async {
    isPlaying = true;
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    calls.add('pause');
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    calls.add('stop');
  }

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
    this.position = position;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
    volumes.add(volume);
  }

  @override
  Future<void> setShuffle(bool enabled) async => shuffleEnabled = enabled;

  @override
  Future<void> setRepeat(String mode) async => repeatMode = mode;

  @override
  Future<void> playSongs(List<MusicItem> songs, {int index = 0}) async {
    played
      ..clear()
      ..addAll(songs);
    currentSong = songs[index];
    isPlaying = true;
    calls.add('playSongs');
  }

  @override
  Future<void> playPlaylist(String playlistId, {int index = 0}) async {
    playedPlaylistId = playlistId;
    playedPlaylistIndex = index;
  }

  @override
  Future<void> enqueue(List<MusicItem> songs, {bool playNext = false}) async {
    enqueued.addAll(songs);
    calls.add(playNext ? 'enqueueNext' : 'enqueueEnd');
  }

  final Set<String> disliked = {};

  @override
  Future<bool> isDisliked(MusicItem song) async =>
      disliked.contains(song.identityKey);

  @override
  Future<void> setDisliked(MusicItem song, bool value) async {
    if (value) {
      disliked.add(song.identityKey);
    } else {
      disliked.remove(song.identityKey);
    }
  }

  Duration? sleepTimer;

  @override
  Future<void> setSleepTimer(Duration? duration) async => sleepTimer = duration;

  @override
  Duration? get sleepTimerRemaining => sleepTimer;
}

class FakePlaylists implements AiPlaylistPort {
  FakePlaylists({List<Playlist>? items, List<MusicItem>? favorites})
    : items = [
        ...?items,
        if (!(items ?? const []).any((item) => item.id == 'favorites'))
          playlist('favorites', '收藏列表', favorites ?? const []),
      ];

  final List<Playlist> items;
  final List<String> deleted = [];
  final List<String> sortedBy = [];

  @override
  Future<List<Playlist>> loadPlaylists() async => List.unmodifiable(items);

  @override
  Future<Playlist?> findPlaylist(String query) async {
    for (final item in items) {
      if (item.id == query) return item;
    }
    for (final item in items) {
      if (item.name == query) return item;
    }
    for (final item in items) {
      if (item.name.contains(query)) return item;
    }
    return null;
  }

  @override
  Future<List<MusicItem>> songsOf(String playlistId) async =>
      items.firstWhere((item) => item.id == playlistId).songs;

  @override
  Future<Playlist> create({
    required String name,
    String? description,
    List<MusicItem> songs = const [],
  }) async {
    final created = playlist('p${items.length + 1}', name, [...songs]);
    items.add(
      Playlist(
        id: created.id,
        name: name,
        description: description,
        songs: created.songs,
        createdAt: created.createdAt,
        updatedAt: created.updatedAt,
      ),
    );
    return items.last;
  }

  @override
  Future<Playlist> update({
    required String id,
    String? name,
    String? description,
  }) async {
    final index = items.indexWhere((item) => item.id == id);
    final updated = items[index].copyWith(name: name, description: description);
    items[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    items.removeWhere((item) => item.id == id);
  }

  @override
  Future<int> addSongs(String playlistId, List<MusicItem> songs) async {
    final index = items.indexWhere((item) => item.id == playlistId);
    final existing = {for (final item in items[index].songs) item.identityKey};
    final additions = [
      for (final item in songs)
        if (existing.add(item.identityKey)) item,
    ];
    items[index] = items[index].copyWith(
      songs: [...items[index].songs, ...additions],
    );
    return additions.length;
  }

  @override
  Future<int> removeSongs(String playlistId, Iterable<String> tokens) async {
    final index = items.indexWhere((item) => item.id == playlistId);
    final wanted = tokens.toSet();
    final kept = [
      for (final item in items[index].songs)
        if (!wanted.contains(item.identityKey) &&
            !wanted.contains(item.playlistItemId))
          item,
    ];
    final removed = items[index].songs.length - kept.length;
    items[index] = items[index].copyWith(songs: kept);
    return removed;
  }

  @override
  Future<bool> sort(
    String playlistId,
    AiPlaylistSortBy by, {
    bool ascending = true,
  }) async {
    sortedBy.add(by.name);
    final index = items.indexWhere((item) => item.id == playlistId);
    final songs = [...items[index].songs];
    songs.sort((a, b) {
      final result = switch (by) {
        AiPlaylistSortBy.name => a.name.compareTo(b.name),
        AiPlaylistSortBy.artist => a.singer.compareTo(b.singer),
        AiPlaylistSortBy.duration => a.duration.compareTo(b.duration),
      };
      return ascending ? result : -result;
    });
    items[index] = items[index].copyWith(songs: songs);
    return true;
  }

  @override
  Future<bool> setFavorite(MusicItem song, bool favorite) async {
    final index = items.indexWhere((item) => item.id == 'favorites');
    final current = items[index].songs;
    if (favorite) {
      if (current.any((item) => item.identityKey == song.identityKey)) {
        return false;
      }
      items[index] = items[index].copyWith(songs: [song, ...current]);
      return true;
    }
    final kept = [
      for (final item in current)
        if (item.identityKey != song.identityKey) item,
    ];
    if (kept.length == current.length) return false;
    items[index] = items[index].copyWith(songs: kept);
    return true;
  }

  @override
  Future<bool> isFavorite(MusicItem song) async => (await songsOf(
    'favorites',
  )).any((item) => item.identityKey == song.identityKey);
}

class FakeDownloads implements AiDownloadPort {
  final List<MusicItem> added = [];
  final List<String> removed = [];
  bool cacheCleared = false;

  @override
  List<DownloadTask> tasks = const [];

  @override
  Future<void> add(List<MusicItem> songs) async => added.addAll(songs);

  @override
  Future<void> remove(String taskId) async => removed.add(taskId);

  @override
  Future<void> clearCache() async => cacheCleared = true;
}

class FakeSources implements AiSourcePort {
  FakeSources({List<CustomSource>? items, this.book = SourceCheckBook.empty})
    : items =
          items ?? [_source('s1', '源一'), _source('s2', '源二', enabled: false)];

  final List<CustomSource> items;
  final List<String?> checks = [];

  SourceCheckBook book;

  @override
  List<CustomSource> get sources => items;

  @override
  SourceCheckBook get checkBook => book;

  @override
  Future<bool> toggle(String id) async {
    final index = items.indexWhere((item) => item.id == id);
    final toggled = _source(
      items[index].id,
      items[index].name,
      enabled: !items[index].isEnabled,
    );
    items[index] = toggled;
    return toggled.isEnabled;
  }

  @override
  Future<void> runCheck(String? sourceId) async => checks.add(sourceId);

  static CustomSource _source(String id, String name, {bool enabled = true}) =>
      CustomSource(
        id: id,
        name: name,
        description: '',
        version: '1.0.0',
        author: 'a',
        script: '//',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isEnabled: enabled,
      );
}

class FakeSettings implements AiSettingsPort {
  @override
  String audioQuality = 'high';

  @override
  String downloadQuality = 'high';

  @override
  bool wifiOnlyDownload = true;

  @override
  String themeMode = 'system';

  @override
  Future<void> setAudioQuality(String token) async => audioQuality = token;

  @override
  Future<void> setDownloadQuality(String token) async =>
      downloadQuality = token;

  @override
  Future<void> setWifiOnlyDownload(bool value) async =>
      wifiOnlyDownload = value;

  @override
  Future<void> setThemeMode(String mode) async => themeMode = mode;
}

class FakeRecommendations implements AiRecommendationPort {
  FakeRecommendations({List<RecommendedSong>? items})
    : _items = [...?items];

  List<RecommendedSong> _items;

  @override
  RecommendationTuning tuning = RecommendationTuning.empty;

  final List<RecommendationTuning> applied = [];
  int refreshes = 0;

  @override
  List<RecommendedSong> get current => _items;

  @override
  bool get hasData => true;

  @override
  Future<List<RecommendedSong>> apply(RecommendationTuning next) async {
    tuning = next;
    applied.add(next);
    return refresh();
  }

  @override
  Future<List<RecommendedSong>> refresh() async {
    refreshes++;
    return _items;
  }

  /// 测试里直接换掉「算法算出来的那批」，模拟重算结果。
  void setItems(List<RecommendedSong> items) => _items = [...items];
}

class FakeEqualizer implements AiEqualizerPort {
  FakeEqualizer({this.supported = true});

  @override
  final bool supported;

  @override
  bool enabled = false;

  @override
  String presetId = 'flat';

  List<double> gains = const [0, 0, 0, 0, 0];

  static const List<double> centers = [60, 230, 910, 3600, 14000];

  final List<String> calls = [];

  @override
  List<({String id, String label})> get presets => const [
    (id: 'flat', label: '平直'),
    (id: 'bass', label: '低音'),
    (id: 'vocal', label: '人声'),
  ];

  @override
  List<AiEqualizerBand> get bands => [
    for (var index = 0; index < centers.length; index++)
      AiEqualizerBand(frequencyHz: centers[index], gainDb: gains[index]),
  ];

  @override
  double get minDecibels => -12;

  @override
  double get maxDecibels => 12;

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
    calls.add('enabled:$value');
  }

  @override
  Future<void> selectPreset(String id) async {
    presetId = id;
    calls.add('preset:$id');
  }

  @override
  Future<bool> setBandGain(double frequencyHz, double gainDb) async {
    var best = 0;
    for (var index = 0; index < centers.length; index++) {
      if ((centers[index] - frequencyHz).abs() <
          (centers[best] - frequencyHz).abs()) {
        best = index;
      }
    }
    final ratio = frequencyHz <= 0 ? 1.0 : centers[best] / frequencyHz;
    if (ratio > 2 || ratio < 0.5) return false;
    final next = [...gains];
    next[best] = gainDb;
    gains = next;
    calls.add('band:${centers[best]}:$gainDb');
    return true;
  }

  @override
  Future<void> resetFlat() async {
    gains = const [0, 0, 0, 0, 0];
    presetId = 'flat';
    calls.add('reset');
  }
}

class FakeStats implements AiStatsPort {
  AiStatsSnapshot? snapshotOverride;

  /// 记录最后一次查询用的范围，方便断言参数透传。
  String? lastRange;

  @override
  AiStatsSnapshot snapshot(String range, {int limit = 10}) {
    lastRange = range;
    return snapshotOverride ??
        AiStatsSnapshot(
          range: range,
          playCount: 42,
          totalSeconds: 3600,
          activeDays: 3,
          songs: const [
            AiRankedEntry(
              title: '晴天',
              subtitle: '周杰伦',
              playCount: 12,
              totalSeconds: 3000,
            ),
          ],
          artists: const [
            AiRankedEntry(
              title: '周杰伦',
              subtitle: '',
              playCount: 20,
              totalSeconds: 5000,
            ),
          ],
          albums: const [],
        );
  }
}

class FakeLyrics implements AiLyricPort {
  List<AiLyricLine>? lines = const [
    AiLyricLine(seconds: 0, text: '故事的小黄花'),
    AiLyricLine(seconds: 5, text: '从出生那年就飘着'),
  ];

  final List<String> requested = [];

  @override
  Future<List<AiLyricLine>?> lyricsOf(MusicItem song) async {
    requested.add(song.name);
    return lines;
  }
}

class FakeCharts implements AiChartPort {
  List<AiChartEntry> entries = const [
    AiChartEntry(id: 'tx:26', name: '热歌榜', platform: 'tx'),
    AiChartEntry(id: 'kw:93', name: '飙升榜', platform: 'kw'),
  ];

  bool songsEmpty = false;

  @override
  Future<List<AiChartEntry>> charts({String? platform}) async => [
    for (final item in entries)
      if (platform == null ||
          item.platform == platform ||
          item.id.startsWith('$platform:'))
        item,
  ];

  @override
  Future<List<MusicItem>> songsOf(String chartId) async =>
      songsEmpty ? const [] : [song('1', '晴天', '周杰伦')];
}

class FakeSchedules implements AiSchedulePort {
  FakeSchedules([List<AiScheduledTask>? initial])
    : tasks = [...?initial];

  @override
  final List<AiScheduledTask> tasks;

  ({bool ok, String summary}) runResult = (ok: true, summary: '好了');

  @override
  Future<AiScheduledTask?> create({
    required String title,
    required String prompt,
    required int minuteOfDay,
    required String cadence,
    int? weekday,
    bool enabled = true,
  }) async {
    final task = AiScheduledTask(
      id: 'task_${tasks.length + 1}',
      title: title,
      prompt: prompt,
      minuteOfDay: minuteOfDay,
      cadence: AiScheduleCadence.values.firstWhere((it) => it.name == cadence),
      weekday: weekday ?? 1,
      enabled: enabled,
    );
    tasks.add(task);
    return task;
  }

  @override
  Future<bool> setEnabled(String id, bool enabled) async {
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0) return false;
    tasks[index] = tasks[index].copyWith(enabled: enabled);
    return true;
  }

  @override
  Future<bool> remove(String id) async {
    final before = tasks.length;
    tasks.removeWhere((task) => task.id == id);
    return tasks.length != before;
  }

  @override
  Future<({bool ok, String summary})> runNow(String id) async => runResult;
}

class FakeLocal implements AiLocalPort {
  int added = 3;
  int calls = 0;

  @override
  Future<int> rescan() async {
    calls++;
    return added;
  }
}

/// 一组默认接入的假端口，测试按需覆盖。
class ToolFakes {
  ToolFakes({
    List<MusicItem>? library,
    List<Playlist>? playlists,
    List<CustomSource>? sources,
    FakeEqualizer? equalizer,
    FakeCharts? charts,
  }) : library = library ?? [song('1', '晴天', '周杰伦'), song('2', '夜曲', '周杰伦')],
       playback = FakePlayback(),
       playlists = FakePlaylists(items: playlists),
       downloads = FakeDownloads(),
       sources = FakeSources(items: sources),
       recommendations = FakeRecommendations(),
       settings = FakeSettings(),
       equalizer = equalizer ?? FakeEqualizer(),
       stats = FakeStats(),
       lyrics = FakeLyrics(),
       charts = charts ?? FakeCharts(),
       schedules = FakeSchedules(),
       local = FakeLocal();

  final List<MusicItem> library;
  final FakePlayback playback;
  final FakePlaylists playlists;
  final FakeDownloads downloads;
  final FakeSources sources;
  final FakeRecommendations recommendations;
  final FakeSettings settings;
  final FakeEqualizer equalizer;
  final FakeStats stats;
  final FakeLyrics lyrics;
  final FakeCharts charts;
  final FakeSchedules schedules;
  final FakeLocal local;
  final List<String> queries = [];

  AiToolbox toolbox({bool allowActions = true}) => AiToolbox(
    allowActions: allowActions,
    playback: playback,
    playlists: playlists,
    downloads: downloads,
    sources: sources,
    recommendations: recommendations,
    settings: settings,
    equalizer: equalizer,
    stats: stats,
    lyrics: lyrics,
    charts: charts,
    schedules: schedules,
    local: local,
    search: (query, limit) async {
      queries.add(query);
      return library.take(limit).toList(growable: false);
    },
  );
}
