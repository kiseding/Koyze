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

/// 猜你喜欢推荐结果。
///
/// 复用内置推荐算法 [RecommendationEngine] 完成排除已收藏、画像评分与
/// Top-N 排序；联网搜索仅为算法补充“未收藏候选”——只用收藏画像中权重
/// 最高的歌手、在收藏最常用的音源上搜索，避免全库检索。搜索失败时自动
/// 降级为本地候选，不影响结果。仅当收藏/播放历史变化（revision 变更）
/// 时才重建，不会反复联网。
final recommendationProvider = FutureProvider<List<RecommendedSong>>((
  ref,
) async {
  ref.watch(playlistRevisionProvider);
  ref.watch(playHistoryRevisionProvider).value;

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
      (a, b) =>
          profile.artistWeights[b]!.compareTo(profile.artistWeights[a]!),
    );
  if (artists.isNotEmpty) {
    final platformId = _dominantPlatform(favorites);
    if (platformId != null) {
      // artistWeights 的键是小写歌手名，映射回原始大小写用于搜索。
      final original = <String, String>{};
      for (final song in favorites) {
        final artist = song.singer.trim();
        if (artist.isNotEmpty) original[artist.toLowerCase()] = artist;
      }
      final sourceManager = ref.read(builtInSourcesProvider);
      final queries =
          artists.take(3).map((a) => original[a] ?? a).toList(growable: false);
      await Future.wait([
        for (final query in queries)
          sourceManager.search(platformId, query, limit: 40).then((songs) {
            for (final song in songs) {
              candidates[song.identityKey] = song;
            }
          }).catchError((_) {}),
      ]);
    }
  }

  return engine.recommend(
    favorites: favorites,
    candidates: candidates.values.toList(),
    playCounts: artistPlays,
  );
});
