import '../../player/domain/music_item.dart';
import 'm3u_playlist.dart';

class M3uImportResult {
  const M3uImportResult({required this.songs, required this.skipped});

  final List<MusicItem> songs;

  /// 清单里有、但本地库里找不到的条目数（含格式坏掉的记录）。
  final int skipped;

  bool get isEmpty => songs.isEmpty;
}

/// 把 M3U 条目对到本地曲库。
///
/// 先按文件路径精确匹配，再退回「标题 + 歌手」：从别的机器或别的播放器
/// 导出的清单，路径几乎一定对不上，但歌名和歌手通常是准的。
M3uImportResult matchM3uToLibrary(M3uDocument doc, List<MusicItem> library) {
  final byPath = <String, MusicItem>{};
  final byName = <String, MusicItem>{};
  for (final song in library) {
    final path = song.meta?['filePath']?.toString();
    if (path != null && path.isNotEmpty) {
      byPath.putIfAbsent(_normalizePath(path), () => song);
    }
    byName.putIfAbsent(_nameKey(song.name, song.singer), () => song);
  }

  final matched = <MusicItem>[];
  final seen = <String>{};
  var skipped = doc.droppedLines;

  for (final entry in doc.entries) {
    final song = _resolve(entry, byPath, byName, library);
    if (song == null) {
      skipped++;
      continue;
    }
    // 清单里同一首歌出现两次时只保留一份，否则新歌单里会有重复行。
    if (seen.add(song.id)) matched.add(song);
  }

  return M3uImportResult(songs: matched, skipped: skipped);
}

MusicItem? _resolve(
  M3uEntry entry,
  Map<String, MusicItem> byPath,
  Map<String, MusicItem> byName,
  List<MusicItem> library,
) {
  final exact = byPath[_normalizePath(_filePathOf(entry.location))];
  if (exact != null) return exact;

  final title = entry.title;
  if (title == null || title.trim().isEmpty) return null;

  final named = byName[_nameKey(title, entry.artist ?? '')];
  if (named != null) return named;

  // 清单只写了歌名（没有歌手）时，只有在曲库里标题唯一才敢认。
  if (entry.artist == null || entry.artist!.trim().isEmpty) {
    final target = _fold(title);
    final candidates = library
        .where((song) => _fold(song.name) == target)
        .toList(growable: false);
    if (candidates.length == 1) return candidates.single;
  }
  return null;
}

String _normalizePath(String path) =>
    path.replaceAll(r'\', '/').toLowerCase();

String _filePathOf(String location) {
  if (location.startsWith('file://')) {
    try {
      return Uri.parse(location).toFilePath();
    } catch (_) {
      return location;
    }
  }
  return location;
}

String _nameKey(String title, String artist) =>
    '${_fold(title)}|${_fold(artist)}';

String _fold(String value) => value.trim().toLowerCase();
