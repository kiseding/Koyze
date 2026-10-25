import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';

import '../domain/lyric.dart';
import '../domain/lyric_service.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../../search/presentation/search_provider.dart';

final lyricServiceProvider = Provider<LyricService>((ref) {
  // 注入 MusicSourceService 以支持统一的歌词获取逻辑
  final musicSourceService = ref.watch(musicSourceServiceProvider);
  final service = LyricService(musicSourceService);
  ref.onDispose(service.dispose);
  return service;
});

typedef LyricLoader = Future<Lyrics> Function(MusicItem music);

final lyricLoaderProvider = Provider<LyricLoader>((ref) {
  return ref.read(lyricServiceProvider).fetchLyric;
});

final currentLyricLoadProvider =
    NotifierProvider<LyricNotifier, LyricLoadState>(LyricNotifier.new);

final currentLyricProvider = Provider<Lyrics>((ref) {
  return ref.watch(currentLyricLoadProvider).lyrics;
});

class LyricLoadState {
  const LyricLoadState({
    required this.lyrics,
    this.isLoading = false,
    this.error,
    this.stackTrace,
  });

  factory LyricLoadState.empty() => LyricLoadState(lyrics: Lyrics.empty());

  final Lyrics lyrics;
  final bool isLoading;
  final Object? error;
  final StackTrace? stackTrace;
}

class LyricNotifier extends BuildlessNotifier<LyricLoadState> {
  LyricNotifier([LyricLoader? load])
    : _loadOverride = load,
      super(LyricLoadState.empty());

  final LyricLoader? _loadOverride;
  LyricLoader get _load =>
      _loadOverride ?? _resolvedLoad ?? (music) async => Lyrics.empty();
  LyricLoader? _resolvedLoad;
  int _generation = 0;
  MusicItem? _selectedMusic;
  String? _selectedLyricId;

  @override
  LyricLoadState build() {
    if (_loadOverride == null) {
      _resolvedLoad = ref.watch(lyricLoaderProvider);
      // Follow the current track for the lifetime of the provider.
      ref.listen<MusicItem?>(currentMusicProvider, (_, next) {
        select(next).ignore();
      }, fireImmediately: true);
    }
    return super.build();
  }

  String _lyricId(MusicItem music) {
    final platform = music.platform.isNotEmpty ? music.platform : music.source;
    final songId = music.songmid?.isNotEmpty == true
        ? music.songmid!
        : music.id;
    return '$platform|$songId|${music.id}';
  }

  Future<void> select(MusicItem? music) async {
    // 同一首歌的元数据刷新（如封面下载后 patchQueueArtUri 触发 mediaItem
    // 变化）不应清空并重新加载歌词，否则逐字歌词会在播放中突然消失。
    final lyricId = music == null ? null : _lyricId(music);
    if (lyricId == _selectedLyricId && value.lyrics.isNotEmpty) {
      _selectedMusic = music;
      return;
    }
    final generation = ++_generation;
    _selectedMusic = music;
    _selectedLyricId = lyricId;
    publish(LyricLoadState(lyrics: Lyrics.empty(), isLoading: music != null));
    if (music == null) return;

    try {
      final lyrics = await _load(music);
      if (!_owns(generation, lyricId!)) return;
      publish(LyricLoadState(lyrics: lyrics));
    } catch (error, stackTrace) {
      if (!_owns(generation, lyricId!)) return;
      publish(
        LyricLoadState(
          lyrics: Lyrics.empty(),
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<void> retry() async {
    final music = _selectedMusic;
    if (music == null) return;
    await select(music);
  }

  bool _owns(int generation, String lyricId) {
    return generation == _generation && lyricId == _selectedLyricId;
  }

  @override
  void onTeardown() {
    _generation++;
    _selectedMusic = null;
    _selectedLyricId = null;
  }
}

// 当前行索引
final currentLineIndexProvider = Provider<int>((ref) {
  final position = ref.watch(playerPositionProvider);
  final lyrics = ref.watch(currentLyricProvider);

  final pos = position;
  return lyrics.getCurrentLineIndex(pos);
});
