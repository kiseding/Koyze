import '../../player/domain/music_item.dart';

/// 专辑曲目页的数据来源。
enum AlbumTracksOrigin {
  /// 平台专辑接口：完整曲目 + 正规顺序，可直接播放。
  platform,

  /// MusicBrainz 曲目表：曲名/顺序权威，但没有音频地址，
  /// 点击时需要回平台按歌名匹配一次。
  musicBrainz,

  /// 兜底：按「歌手 + 专辑」搜索后按专辑名过滤，只拿到搜索能命中的那些。
  search,
}

/// 从歌曲原始元数据里取所在专辑的平台 id。
///
/// 三个平台字段各不相同：QQ 用 `albummid`，网易把专辑放在 `al`（或
/// `album`）里，酷狗用 `AlbumID`/`album_id`。取不到就返回空串，
/// 调用方会走 MusicBrainz 兜底。
String albumIdOf(MusicItem song) {
  final meta = song.meta;
  if (meta == null || meta.isEmpty) return '';

  String read(Object? value) => value?.toString().trim() ?? '';

  switch (song.platform.toLowerCase()) {
    case 'tx':
      final mid = read(meta['albummid']);
      return mid == '空' ? '' : mid;
    case 'wy':
      for (final key in const ['al', 'album']) {
        final nested = meta[key];
        if (nested is Map) {
          final id = read(nested['id']);
          if (id.isNotEmpty) return id;
        }
      }
      return '';
    case 'kg':
      for (final key in const ['AlbumID', 'album_id']) {
        final id = read(meta[key]);
        if (id.isNotEmpty) return id;
      }
      return '';
    case 'kw':
      for (final key in const ['ALBUMID', 'albumid']) {
        final id = read(meta[key]);
        if (id.isNotEmpty) return id;
      }
      return '';
    default:
      return '';
  }
}

/// 专辑名比较用的归一化：大小写、空白与常见中英标点不参与比较。
String normalizeAlbumName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\u3000\-_.!,?()（）【】\[\]「」『』:：·&/]'), '')
    .replaceAll(RegExp(r'["\u2018\u2019\u201C\u201D]'), '');

/// 把专辑接口返回的曲目补齐成完整可展示的形状。
///
/// 平台接口偶尔不返回专辑名或歌手名（酷狗就没有 singername），
/// 这里用页面已知的专辑名/歌手名兜底，避免列表出现空白副标题。
List<MusicItem> fillAlbumIdentity(
  List<MusicItem> songs, {
  required String albumName,
  required String artistName,
}) {
  if (songs.isEmpty) return songs;
  return songs
      .map((song) {
        final needsAlbum = song.album.trim().isEmpty;
        final needsArtist =
            song.singer.trim().isEmpty || song.singer.trim() == '未知歌手';
        if (!needsAlbum && !needsArtist) return song;
        return song.copyWith(
          album: needsAlbum ? albumName : null,
          singer: needsArtist && artistName.isNotEmpty ? artistName : null,
        );
      })
      .toList(growable: false);
}

/// 在搜索结果里挑出确实属于该专辑的歌（兜底用）。
List<MusicItem> songsInAlbum(
  Iterable<MusicItem> songs, {
  required String albumName,
  required String artistName,
}) {
  final wanted = normalizeAlbumName(albumName);
  if (wanted.isEmpty) return const [];
  final wantedArtist = artistName.trim().toLowerCase();
  return songs
      .where((song) {
        if (!song.isPlayable) return false;
        if (normalizeAlbumName(song.album) != wanted) return false;
        if (wantedArtist.isEmpty) return true;
        final singer = song.singer.toLowerCase();
        return singer.isEmpty || singer.contains(wantedArtist);
      })
      .toList(growable: false);
}
