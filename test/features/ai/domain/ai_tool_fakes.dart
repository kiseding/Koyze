import 'package:koyze/features/ai/domain/ai_action_ports.dart';
import 'package:koyze/features/ai/domain/ai_tools.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/download/domain/download_task.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
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

/// 一组默认接入的假端口，测试按需覆盖。
class ToolFakes {
  ToolFakes({
    List<MusicItem>? library,
    List<Playlist>? playlists,
    List<CustomSource>? sources,
  }) : library = library ?? [song('1', '晴天', '周杰伦'), song('2', '夜曲', '周杰伦')],
       playback = FakePlayback(),
       playlists = FakePlaylists(items: playlists),
       downloads = FakeDownloads(),
       sources = FakeSources(items: sources),
       settings = FakeSettings();

  final List<MusicItem> library;
  final FakePlayback playback;
  final FakePlaylists playlists;
  final FakeDownloads downloads;
  final FakeSources sources;
  final FakeSettings settings;
  final List<String> queries = [];

  AiToolbox toolbox({bool allowActions = true}) => AiToolbox(
    allowActions: allowActions,
    playback: playback,
    playlists: playlists,
    downloads: downloads,
    sources: sources,
    settings: settings,
    search: (query, limit) async {
      queries.add(query);
      return library.take(limit).toList(growable: false);
    },
  );
}
