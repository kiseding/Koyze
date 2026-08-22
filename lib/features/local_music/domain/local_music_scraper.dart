import 'package:koyze/core/network/music_source_service.dart';
import 'package:koyze/features/player/domain/music_item.dart';

import 'local_music_scanner.dart';

/// 刮削结果：本地文件路径 → 在线歌曲身份。
class ScrapeIdentity {
  const ScrapeIdentity({
    required this.platform,
    required this.songmid,
    required this.name,
    required this.singer,
    this.hash,
    this.album = '',
    this.artwork,
    this.lyricsUrl,
    this.lyrics,
  });

  final String platform;
  final String songmid;
  final String name;
  final String singer;
  final String album;
  final String? hash;
  final String? artwork;
  final String? lyricsUrl;
  final String? lyrics;

  ScrapeIdentity copyWith({
    String? artwork,
    String? lyricsUrl,
    String? lyrics,
  }) {
    return ScrapeIdentity(
      platform: platform,
      songmid: songmid,
      hash: hash,
      name: name,
      singer: singer,
      album: album,
      artwork: artwork ?? this.artwork,
      lyricsUrl: lyricsUrl ?? this.lyricsUrl,
      lyrics: lyrics ?? this.lyrics,
    );
  }

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'songmid': songmid,
    'hash': hash,
    'name': name,
    'singer': singer,
    'album': album,
    'artwork': artwork,
    'lyricsUrl': lyricsUrl,
    'lyrics': lyrics,
  };
}

/// 从没有内嵌 tag 的文件名中提取的搜索候选。
final class LocalFilenameQuery {
  const LocalFilenameQuery({required this.title, this.artist = ''});

  final String title;
  final String artist;

  @override
  bool operator ==(Object other) =>
      other is LocalFilenameQuery &&
      other.title == title &&
      other.artist == artist;

  @override
  int get hashCode => Object.hash(title, artist);
}

/// 本地歌曲在线匹配（刮削）：
/// 1. 用「歌手 + 歌名」在音乐源搜索
/// 2. 精确匹配标题（忽略大小写）并校验时长容差（±2s 或未知时长）
/// 3. 回填在线身份（songmid/hash/artwork/lyricsUrl）
class LocalMusicScraper {
  LocalMusicScraper(this._musicSourceService);

  static const _durationToleranceSeconds = 2;
  static const _minimumFilenameMatchScore = 7;

  final MusicSourceService _musicSourceService;

  Future<ScrapeIdentity?> scrapeTrack(LocalTrack track) async {
    final queries = track.hasEmbeddedTags
        ? [LocalFilenameQuery(title: track.title, artist: track.artist)]
        : filenameQueries(track.fileName);
    if (queries.isEmpty) return null;
    try {
      final platformResults = await Future.wait(
        MusicSourceService.fallbackPlatforms.map((platform) async {
          final results = <MusicItem>[];
          for (final query in queries) {
            final keyword = [
              query.artist,
              query.title,
            ].where((value) => value.trim().isNotEmpty).join(' ');
            if (keyword.isEmpty) continue;
            results.addAll(
              await _musicSourceService.builtInSources
                  .search(platform, keyword, page: 1, limit: 10)
                  .timeout(const Duration(seconds: 10))
                  .catchError((_) => <MusicItem>[]),
            );
          }
          return results;
        }),
      );
      final matches = [
        for (final results in platformResults)
          if (bestMatchForQueries(track, queries, results) case final match?)
            match,
      ];
      final match = matches.isEmpty ? null : matches.first;
      if (match == null) return null;

      // 搜索结果中的封面可能是缩略图。内置音源再走一次平台封面接口，
      // 例如酷我使用 500x500 图床；不支持高清接口时保留搜索结果。
      final matchedSong = platformResults
          .expand((results) => results)
          .cast<MusicItem?>()
          .firstWhere(
            (song) =>
                song != null &&
                song.platform == match.platform &&
                (song.songmid == match.songmid || song.hash == match.hash),
            orElse: () => null,
          );
      var enriched = match;
      if (matchedSong != null &&
          const {'kw', 'tx', 'wy'}.contains(matchedSong.platform)) {
        final highResolution = await _musicSourceService.builtInSources
            .getArtwork(matchedSong.platform, matchedSong);
        if (highResolution != null && highResolution.isNotEmpty) {
          enriched = enriched.copyWith(artwork: highResolution);
        }
      }
      enriched = enriched.copyWith(
        artwork: highResolutionArtworkUrl(enriched.platform, enriched.artwork),
      );
      final lyrics = await _musicSourceService.getLyric(
        MusicItem(
          id: enriched.songmid,
          name: enriched.name,
          singer: enriched.singer,
          album: enriched.album,
          source: enriched.platform,
          platform: enriched.platform,
          songmid: enriched.songmid,
          hash: enriched.hash,
        ),
      );
      return enriched.copyWith(lyrics: lyrics);
    } catch (error) {
      return null;
    }
  }

  /// 纯函数：从搜索结果中挑选完全匹配（标题一致 + 时长容差）。
  /// 单独公开以便测试。
  static ScrapeIdentity? bestMatch(LocalTrack track, List<MusicItem> results) {
    return bestMatchForQueries(track, [
      LocalFilenameQuery(title: track.title, artist: track.artist),
    ], results);
  }

  static ScrapeIdentity? bestMatchForQueries(
    LocalTrack track,
    List<LocalFilenameQuery> queries,
    List<MusicItem> results,
  ) {
    final candidates = <({MusicItem song, int score})>[];
    for (final song in results) {
      for (final query in queries) {
        final normalizedTitle = _normalize(query.title);
        final normalizedArtist = _normalize(query.artist);
        final normalizedSongTitle = _normalize(song.name);
        if (normalizedSongTitle != normalizedTitle) continue;
        var score = 6;
        if (track.duration > Duration.zero && song.duration > Duration.zero) {
          final diff = (song.duration.inSeconds - track.duration.inSeconds)
              .abs();
          if (diff > _durationToleranceSeconds) continue;
          score += diff == 0 ? 3 : 2;
        } else if (query.artist.isEmpty) {
          // 纯歌名且没有时长时可能重名，不自动写入刮削身份。
          continue;
        }
        if (normalizedArtist.isNotEmpty) {
          final normalizedSongArtist = _normalize(song.singer);
          if (normalizedSongArtist == normalizedArtist) {
            score += 4;
          } else if (normalizedSongArtist.contains(normalizedArtist) ||
              normalizedArtist.contains(normalizedSongArtist)) {
            score += 2;
          }
        }
        final normalizedAlbum = _normalize(track.album);
        if (normalizedAlbum.isNotEmpty &&
            _normalize(song.album).contains(normalizedAlbum)) {
          score++;
        }
        if (!track.hasEmbeddedTags && score < _minimumFilenameMatchScore) {
          continue;
        }
        final songmid = song.songmid ?? song.hash;
        if (songmid == null || songmid.isEmpty) continue;
        candidates.add((song: song, score: score));
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final song = candidates.first.song;
    return ScrapeIdentity(
      platform: song.platform,
      songmid: song.songmid ?? song.hash!,
      hash: song.hash,
      name: song.name,
      singer: song.singer,
      album: song.album,
      artwork: song.artwork,
      lyricsUrl: song.lyricsUrl,
      lyrics: null,
    );
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u2010-\u2015]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// 解析常见文件名格式，并保留两个方向供在线结果评分：
  /// `歌手 - 歌名` 与 `歌名 - 歌手` 无法仅靠分隔符可靠区分。
  static List<LocalFilenameQuery> filenameQueries(String fileName) {
    final stem = _cleanFilename(fileName);
    if (stem.isEmpty) return const [];
    final parts = stem
        .split(RegExp(r'\s*[-–—]\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 3 && RegExp(r'^\d{1,3}$').hasMatch(parts.first)) {
      parts.removeAt(0);
    }
    if (parts.length == 2) {
      final first = parts[0];
      final second = parts[1];
      return [
        LocalFilenameQuery(title: second, artist: first),
        LocalFilenameQuery(title: first, artist: second),
      ];
    }
    return [LocalFilenameQuery(title: stem)];
  }

  static String _cleanFilename(String fileName) {
    final dot = fileName.lastIndexOf('.');
    var stem = (dot > 0 ? fileName.substring(0, dot) : fileName).trim();
    stem = stem.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-._]\s*'), '');
    stem = stem.replaceAll(RegExp(r'\s*\[(?:[^\]]+)\]\s*$'), '');
    stem = stem.replaceAll(RegExp(r'\s*\((?:[^\)]+)\)\s*$'), '');
    stem = stem.replaceAll(
      RegExp(
        r'\s*[-_]\s*(?:\d{3,4}k|\d{2,3}kbps|flac|mp3|aac)\s*$',
        caseSensitive: false,
      ),
      '',
    );
    return stem.trim();
  }

  /// 将搜索接口常见的缩略图 URL 升级为适合播放器展示的大图 URL。
  static String? highResolutionArtworkUrl(String platform, String? artwork) {
    if (artwork == null || artwork.isEmpty) return artwork;
    switch (platform) {
      case 'tx':
        return artwork
            .replaceAll('T001R500x500', 'T001R1000x1000')
            .replaceAll('T002R500x500', 'T002R1000x1000');
      case 'wy':
        return '${artwork.split('?').first}?param=1000y1000';
      case 'kw':
        return artwork.replaceFirst('/120/', '/500/');
      default:
        return artwork;
    }
  }

  /// Ordered artwork fallbacks. Some CDNs expose metadata for a 1000px URL
  /// but reject that exact rendition while the original 500px image works.
  static List<String> artworkCandidates(String platform, String? artwork) {
    if (artwork == null || artwork.isEmpty) return const [];
    final upgraded = highResolutionArtworkUrl(platform, artwork);
    final candidates = <String>{
      if (upgraded != null && upgraded.isNotEmpty) upgraded,
      artwork,
    };
    switch (platform) {
      case 'tx':
        candidates.add(
          (upgraded ?? artwork)
              .replaceAll('R1000x1000', 'R500x500')
              .replaceAll('R800x800', 'R500x500'),
        );
      case 'wy':
        candidates
          ..add('${artwork.split('?').first}?param=500y500')
          ..add(artwork.split('?').first);
      case 'kw':
        candidates
          ..add(artwork.replaceFirst('/500/', '/300/'))
          ..add(artwork.replaceFirst('/500/', '/120/'));
    }
    return candidates.where((value) => value.isNotEmpty).toList();
  }
}
