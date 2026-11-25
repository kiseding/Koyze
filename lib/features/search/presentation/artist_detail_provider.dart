import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/artist_songs.dart';
import '../domain/music_brainz_discography.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../../nas/domain/nas_kind.dart';
import '../../nas/presentation/nas_provider.dart';
import '../../player/domain/music_item.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../subsonic/presentation/subsonic_provider.dart';
import 'search_provider.dart';

typedef ArtistQuery = ({String name, String platform, String source});

final artistDiscographyDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': musicBrainzUserAgent,
      },
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// 进程内单例：缓存和节流队列都挂在它身上，切页面不会重置速率窗口。
final musicBrainzDiscographyProvider = Provider<MusicBrainzDiscography>((ref) {
  return MusicBrainzDiscography(ref.watch(artistDiscographyDioProvider));
});

/// 用 MusicBrainz 的发行目录补齐歌手页专辑年份。
///
/// MusicBrainz 无 API key，但要求平均不超过 1 req/sec，所以这里不做并发，
/// 而是交给 [MusicBrainzDiscography] 的请求闸门串行化；结果按歌手缓存。
Future<List<MusicItem>> enrichArtistAlbumDates(
  MusicBrainzDiscography discography,
  String artistName,
  List<MusicItem> songs,
) async {
  if (artistName.trim().isEmpty || songs.isEmpty) return songs;
  final releases = await discography.releasesFor(artistName);
  return applyMusicBrainzReleaseDates(songs, releases);
}

final artistSongsProvider = FutureProvider.autoDispose
    .family<List<MusicItem>, ArtistQuery>((ref, query) async {
      final name = query.name.trim();
      if (name.isEmpty) return const [];

      final kind =
          NasKind.tryParse(query.platform) ?? NasKind.tryParse(query.source);
      if (query.platform == 'local' || query.source == 'local') {
        ref.watch(localMusicRevisionProvider);
        final library = await ref.watch(localMusicLibraryProvider.future);
        await library.init();
        return songsForArtist(library.songs, name);
      }
      if (query.platform == 'favorites' || query.source == 'favorites') {
        final songs = await ref
            .read(playlistServiceProvider)
            .getAllSongs('favorites');
        return songsForArtist(songs, name);
      }
      if (query.platform == 'subsonic' || query.source == 'subsonic') {
        return songsForArtist(
          await ref.watch(subsonicLibrarySongsProvider.future),
          name,
        );
      }
      if (kind != null) {
        return songsForArtist(
          await ref.watch(nasLibrarySongsProvider(kind).future),
          name,
        );
      }

      final service = ref.watch(musicSourceServiceProvider);
      final sourceId = query.source.isNotEmpty ? query.source : query.platform;
      const pageSize = 100;
      const maxPages = 10;
      final candidates = <MusicItem>[];
      final seen = <String>{};
      for (var page = 1; page <= maxPages; page++) {
        final batch = await service.search(
          name,
          customSourceId: sourceId,
          page: page,
          limit: pageSize,
          type: 'music',
        );
        for (final song in batch) {
          if (seen.add(song.identityKey)) candidates.add(song);
        }
        if (batch.length < pageSize) break;
      }
      final artistSongs = songsForArtist(candidates, name);
      return enrichArtistAlbumDates(
        ref.watch(musicBrainzDiscographyProvider),
        name,
        artistSongs,
      );
    });
