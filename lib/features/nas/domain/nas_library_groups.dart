import '../../player/domain/music_item.dart';

/// 自建乐库的分组方式。
enum NasGrouping { album, artist, folder }

/// 一个分组（专辑 / 艺术家 / 文件夹）。
class NasCollection {
  const NasCollection({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.songs,
    this.artwork,
  });

  final String key;
  final String title;
  final String subtitle;
  final List<MusicItem> songs;
  final String? artwork;
}

/// 把平铺的歌曲列表按 [grouping] 分组。
///
/// WebDAV 没有服务端专辑概念，专辑/艺术家只能靠目录结构和文件名推出来；
/// 这里只负责分组，缺标签时用 [unknownAlbum] / [unknownArtist] 兜底。
List<NasCollection> groupNasSongs(
  List<MusicItem> songs,
  NasGrouping grouping, {
  String unknownAlbum = '',
  String unknownArtist = '',
}) {
  final buckets = <String, List<MusicItem>>{};
  final titles = <String, String>{};
  final subtitles = <String, String>{};

  for (final song in songs) {
    final String key;
    final String title;
    final String subtitle;
    switch (grouping) {
      case NasGrouping.album:
        final album = song.album.trim();
        final artist = song.singer.trim();
        key = '$album|$artist';
        title = album.isEmpty ? unknownAlbum : album;
        subtitle = artist;
      case NasGrouping.artist:
        final artist = song.singer.trim();
        key = artist;
        title = artist.isEmpty ? unknownArtist : artist;
        subtitle = '';
      case NasGrouping.folder:
        final folder = (song.meta?['folder']?.toString() ?? '').trim();
        key = folder;
        final segments = folder
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .toList(growable: false);
        title = segments.isEmpty ? '/' : segments.last;
        subtitle = folder;
    }
    buckets.putIfAbsent(key, () => <MusicItem>[]).add(song);
    titles[key] = title;
    subtitles[key] = subtitle;
  }

  final collections = buckets.entries.map((entry) {
    String? artwork;
    for (final song in entry.value) {
      final value = song.artwork;
      if (value != null && value.isNotEmpty) {
        artwork = value;
        break;
      }
    }
    return NasCollection(
      key: entry.key,
      title: titles[entry.key] ?? entry.key,
      subtitle: subtitles[entry.key] ?? '',
      songs: List<MusicItem>.unmodifiable(entry.value),
      artwork: artwork,
    );
  }).toList(growable: false);

  collections.sort(
    (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );
  return collections;
}
