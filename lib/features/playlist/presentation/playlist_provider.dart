import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/playlist_repository.dart';
import '../domain/playlist_service.dart';
import '../domain/playlist.dart';
import '../../player/domain/music_item.dart';
import '../../../startup_lifecycle.dart';
import '../../../core/pagination/page_range.dart';
import '../../sync/presentation/sync_phase1_provider.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  throw StateError('playlistRepositoryProvider must be overridden at startup');
});

final playlistServiceProvider = Provider<PlaylistService>((ref) {
  final service = PlaylistService(
    repository: ref.watch(playlistRepositoryProvider),
    syncRecorder: ({required eventType, required entityId, required payload}) =>
        ref
            .read(syncPhase1ServiceProvider)
            .enqueue(
              eventType: eventType,
              entityId: entityId,
              payload: payload,
            ),
  );
  ref.read(syncPhase1ServiceProvider).attachPlaylists(service);
  final disposals = ref.read(resourceDisposalTrackerProvider);
  ref.onDispose(disposals.register(service.dispose));
  return service;
});

final playlistRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(playlistServiceProvider).revisions;
});

final playlistPageRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(playlistServiceProvider).pageRevisions;
});

final playlistRecentRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(playlistServiceProvider).recentRevisions;
});

final playlistSyncRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(playlistServiceProvider).syncRevisions;
});

final playlistFavoritesRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(playlistServiceProvider).favoritesRevisions;
});

final playlistsProvider = Provider<List<Playlist>>((ref) {
  ref.watch(playlistRevisionProvider);
  final playlistService = ref.watch(playlistServiceProvider);
  return playlistService.playlists;
});

final class PlaylistSongsPageRequest {
  const PlaylistSongsPageRequest({
    required this.playlistId,
    required this.pageIndex,
  });

  final String playlistId;
  final int pageIndex;

  int get offset => pageIndex * PageRange.defaultPageSize;

  @override
  bool operator ==(Object other) =>
      other is PlaylistSongsPageRequest &&
      other.playlistId == playlistId &&
      other.pageIndex == pageIndex;

  @override
  int get hashCode => Object.hash(playlistId, pageIndex);
}

final playlistSongsPageProvider = FutureProvider.autoDispose
    .family<PlaylistSongPage, PlaylistSongsPageRequest>((ref, request) {
      ref.watch(playlistPageRevisionProvider);
      if (request.playlistId == 'recent') {
        ref.watch(playlistRecentRevisionProvider);
      }
      if (request.playlistId == 'favorites') {
        ref.watch(playlistFavoritesRevisionProvider);
      }
      return ref
          .read(playlistServiceProvider)
          .getSongsPage(
            request.playlistId,
            offset: request.offset,
            limit: PageRange.defaultPageSize,
          );
    });

/// Clicking the heart should drop the row before persistence finishes.
final optimisticFavoritePageProvider =
    StateProvider<PlaylistSongPage?>((ref) => null);

final playlistSongSearchProvider = FutureProvider.autoDispose
    .family<List<PlaylistSongMatch>, String>((ref, query) {
      ref.watch(playlistRevisionProvider);
      return ref.read(playlistServiceProvider).searchSongs(query);
    });

/// 完整加载的歌单列表（内存中的惰性摘要不含歌曲，需 hydrate 后使用）。
final hydratedPlaylistsProvider = FutureProvider<List<Playlist>>((ref) {
  ref.watch(playlistRevisionProvider);
  return ref.read(playlistServiceProvider).getAllPlaylists();
});

Future<({Set<String> ids, List<MusicItem> songs})> _loadFavoriteState(
  Ref ref,
) async {
  ref.watch(playlistFavoritesRevisionProvider);
  final playlistService = ref.read(playlistServiceProvider);
  final favorites = playlistService.favorites;
  if (favorites == null || favorites.songCount == 0) {
    return (ids: const <String>{}, songs: const <MusicItem>[]);
  }
  final songs = await playlistService.getAllSongs('favorites');
  final rawIdCounts = <String, int>{};
  for (final song in songs) {
    rawIdCounts.update(song.id, (count) => count + 1, ifAbsent: () => 1);
  }
  return (
    ids: {
      for (final song in songs) ...[
        song.identityKey,
        if (song.playlistItemId != null && song.playlistItemId!.isNotEmpty)
          song.playlistItemId!,
        if (rawIdCounts[song.id] == 1) song.id,
      ],
    },
    songs: songs,
  );
}

final isSongFavoriteProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  songId,
) async {
  final state = await _loadFavoriteState(ref);
  if (state.ids.contains(songId)) return true;
  return state.songs.any((song) => song.matchesCollectionId(songId));
});

/// 收藏 id 集合（identityKey / 唯一 raw id / playlistItemId）。
/// 供歌曲列表页面一次读取，避免每个可见行单独创建异步收藏查询。
final favoriteIdsProvider = FutureProvider<Set<String>>((ref) async {
  return (await _loadFavoriteState(ref)).ids;
});

/// 完整收藏曲目。列表红心不能只比 identityKey：同步下来的条目
/// 可能缺 platform / source，字符串对不上但仍是同一首歌。
final favoriteSongsProvider = FutureProvider<List<MusicItem>>((ref) async {
  return (await _loadFavoriteState(ref)).songs;
});

bool isFavoriteMusic(MusicItem song, List<MusicItem> favorites) {
  return _isFavoriteSong(song, favorites);
}

bool _isFavoriteSong(MusicItem song, List<MusicItem> favorites) {
  return favorites.any((item) => item.isSameCatalogTrack(song));
}

// 切换收藏状态
final toggleFavoriteProvider = Provider<Future<void> Function(MusicItem)>((
  ref,
) {
  return (MusicItem song) async {
    final playlistService = ref.read(playlistServiceProvider);
    final favorites = await playlistService.getAllSongs('favorites');
    MusicItem? matched;
    for (final item in favorites) {
      if (item.isSameCatalogTrack(song)) {
        matched = item;
        break;
      }
    }
    if (matched != null) {
      await playlistService.removeSongFromPlaylist(
        'favorites',
        matched.identityKey,
      );
    } else {
      await playlistService.addSongToPlaylist('favorites', song);
    }
  };
});

/// 立刻从当前收藏页拿掉/加回一首歌，不等分页 Future 重新加载。
PlaylistSongPage applyOptimisticFavoritePage({
  required PlaylistSongPage page,
  required MusicItem song,
  required bool favorited,
}) {
  if (favorited) {
    if (page.songs.any((item) => item.isSameCatalogTrack(song))) return page;
    return PlaylistSongPage(
      total: page.total + 1,
      offset: page.offset,
      songs: [song, ...page.songs],
    );
  }
  final kept = [
    for (final item in page.songs)
      if (!item.isSameCatalogTrack(song)) item,
  ];
  if (kept.length == page.songs.length) return page;
  return PlaylistSongPage(
    total: (page.total - (page.songs.length - kept.length)).clamp(0, 1 << 30),
    offset: page.offset,
    songs: kept,
  );
}

// 添加歌曲到指定歌单
final addSongToPlaylistProvider =
    Provider<Future<void> Function(String playlistId, MusicItem)>((ref) {
      return (String playlistId, MusicItem song) async {
        final playlistService = ref.read(playlistServiceProvider);
        await playlistService.addSongToPlaylist(playlistId, song);
      };
    });

// 创建新歌单
final createPlaylistProvider =
    Provider<Future<void> Function(String name, {String? description})>((ref) {
      return (String name, {String? description}) async {
        final playlistService = ref.read(playlistServiceProvider);
        await playlistService.createPlaylist(
          name: name,
          description: description,
        );
      };
    });
