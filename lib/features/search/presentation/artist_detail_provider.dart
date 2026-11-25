import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/artist_songs.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../../nas/domain/nas_kind.dart';
import '../../nas/presentation/nas_provider.dart';
import '../../player/domain/music_item.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../subsonic/presentation/subsonic_provider.dart';
import 'search_provider.dart';

typedef ArtistQuery = ({String name, String platform, String source});

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
      return songsForArtist(candidates, name);
    });
