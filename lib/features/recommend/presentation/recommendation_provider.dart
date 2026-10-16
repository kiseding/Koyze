import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leaderboard/presentation/leaderboard_provider.dart';
import '../../player/domain/music_item.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../stats/presentation/play_history_provider.dart';
import '../domain/recommendation_engine.dart';

/// 收藏中最常出现的音源 id（用于搜索补充候选）。
String? _dominantPlatform(List<MusicItem> favorites) {
  final counts = <String, int>{};
  for (final song in favorites) {
    final platform = song.platform.toLowerCase();
    if (platform.isNotEmpty) {
      counts[platform] = (counts[platform] ?? 0) + 1;
    }
  }
  String? best;
  var max = 0;
  counts.forEach((platform, count) {
    if (count > max) {
      max = count;
      best = platform;
    }
  });
  return best;
}

List<String> recommendationSearchPlatforms({
  required String? dominantPlatform,
  required List<String> availablePlatforms,
}) {
  const preferredFallback = ['kw', 'tx', 'wy'];
  final result = <String>[];
  void add(String? platform) {
    if (platform == null || platform.isEmpty) return;
    if (!availablePlatforms.contains(platform)) return;
    if (!result.contains(platform)) result.add(platform);
  }

  add(dominantPlatform);
  for (final platform in preferredFallback) {
    add(platform);
  }
  for (final platform in availablePlatforms) {
    add(platform);
  }
  return result;
}

/// 推荐结果缓存时长：期间点击播放、收藏变动都不会触发重建，
/// 只有缓存过期后才重新计算一次。
const Duration kRecommendationCacheTtl = Duration(hours: 12);

/// 猜你喜欢推荐结果。
///
/// 复用内置推荐算法 [RecommendationEngine] 完成排除已收藏、画像评分与
/// Top-N 排序；联网搜索仅为算法补充“未收藏候选”。结果带 12 小时 TTL，
/// 播放行为不再触发刷新（避免点一首歌整页重建）。
final recommendationProvider =
    StateNotifierProvider<
      RecommendationNotifier,
      AsyncValue<List<RecommendedSong>>
    >((ref) {
      return RecommendationNotifier(loader: () => computeRecommendations(ref));
    });

class RecommendationNotifier
    extends StateNotifier<AsyncValue<List<RecommendedSong>>> {
  RecommendationNotifier({
    required Future<List<RecommendedSong>> Function() loader,
  }) : _loader = loader,
       super(const AsyncValue.loading()) {
    _ensureData();
  }

  final Future<List<RecommendedSong>> Function() _loader;
  Timer? _refreshTimer;
  DateTime? _loadedAt;
  bool _inFlight = false;
  int _generation = 0;

  bool get _expired =>
      _loadedAt == null ||
      DateTime.now().difference(_loadedAt!) >= kRecommendationCacheTtl;

  Future<void> _ensureData({bool force = false}) async {
    if (_inFlight) return;
    if (!force && !_expired) return;
    _inFlight = true;
    final generation = ++_generation;
    try {
      final result = await _loader();
      if (!mounted || generation != _generation) return;
      _loadedAt = DateTime.now();
      state = AsyncValue.data(result);
      _scheduleNextRefresh();
    } catch (error, stackTrace) {
      if (mounted && generation == _generation) {
        state = AsyncValue.error(error, stackTrace);
      }
    } finally {
      if (generation == _generation) _inFlight = false;
    }
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    final age = _loadedAt == null
        ? Duration.zero
        : DateTime.now().difference(_loadedAt!);
    final remaining = kRecommendationCacheTtl - age;
    _refreshTimer = Timer(
      remaining <= Duration.zero ? const Duration(seconds: 1) : remaining,
      () => _ensureData(force: true),
    );
  }

  /// 错误页手动重试：强制绕过 TTL 重新计算。
  Future<void> retry() {
    _refreshTimer?.cancel();
    _inFlight = false;
    return _ensureData(force: true);
  }

  @override
  void dispose() {
    _generation++;
    _refreshTimer?.cancel();
    super.dispose();
  }
}

/// 计算推荐结果。不 watch 任何 revision，避免播放/收藏变化导致重建。
Future<List<RecommendedSong>> computeRecommendations(Ref ref) async {
  final playlistService = ref.read(playlistServiceProvider);
  final history = ref.read(playHistoryStoreProvider);

  // 使用完整加载的歌单（内存中的惰性摘要不含歌曲列表）。
  final hydrated = await playlistService.getAllPlaylists();
  final favorites = hydrated
      .where((playlist) => playlist.id == 'favorites')
      .expand((playlist) => playlist.songs)
      .toList(growable: false);

  // 本地候选池：所有歌单的歌曲去重（收藏列表与最近播放不参与候选）
  final seen = <String, MusicItem>{};
  for (final playlist in hydrated) {
    if (playlist.id == 'favorites' || playlist.id == 'recent') continue;
    for (final song in playlist.songs) {
      seen[song.identityKey] = song;
    }
  }

  // 播放历史：按歌手聚合次数（隐式反馈）
  final artistPlays = <String, int>{};
  for (final entry in history.entries) {
    if (entry.artistName.isEmpty) continue;
    artistPlays[entry.artistName] = (artistPlays[entry.artistName] ?? 0) + 1;
  }

  final engine = const RecommendationEngine();
  final candidates = <String, MusicItem>{...seen};

  // 只有收藏列表等场景下本地候选不足时，用常听歌手经音源搜索补充
  // 未收藏候选（交给内置算法评分排序，保证猜你喜欢能填满 30 首）。
  final profile = engine.buildProfile(favorites);
  final artists = profile.artistWeights.keys.toList()
    ..sort(
      (a, b) => profile.artistWeights[b]!.compareTo(profile.artistWeights[a]!),
    );
  if (artists.isNotEmpty) {
    final sourceManager = ref.read(builtInSourcesProvider);
    final platformIds = recommendationSearchPlatforms(
      dominantPlatform: _dominantPlatform(favorites),
      availablePlatforms: sourceManager.allIds,
    );
    if (platformIds.isNotEmpty) {
      // artistWeights 的键是小写歌手名，映射回原始大小写用于搜索。
      final original = <String, String>{};
      for (final song in favorites) {
        final artist = song.singer.trim();
        if (artist.isNotEmpty) original[artist.toLowerCase()] = artist;
      }
      final queries = artists
          .take(6)
          .map((a) => original[a] ?? a)
          .toList(growable: false);
      await Future.wait([
        for (final query in queries)
          for (final platformId in platformIds)
            sourceManager
                .search(platformId, query, limit: 40)
                .then((songs) {
                  for (final song in songs) {
                    candidates[song.identityKey] = song;
                  }
                })
                .catchError((_) {}),
      ]);
    }
  }

  return engine.recommend(
    favorites: favorites,
    candidates: candidates.values.toList(),
    playCounts: artistPlays,
  );
}
