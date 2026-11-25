import '../../../core/text/artist_names.dart';
import '../../player/domain/music_item.dart';

List<MusicItem> songsForArtist(Iterable<MusicItem> songs, String artist) {
  final wanted = artist.trim().toLowerCase();
  if (wanted.isEmpty) return const [];
  return songs
      .where(
        (song) =>
            song.isPlayable &&
            artistNamesOf(
              song.singer,
            ).any((name) => name.trim().toLowerCase() == wanted),
      )
      .toList(growable: false);
}
