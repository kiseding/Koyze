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

/// 本地歌曲在线匹配（刮削）：
/// 1. 用「歌手 + 歌名」在音乐源搜索
/// 2. 精确匹配标题（忽略大小写）并校验时长容差（±2s 或未知时长）
/// 3. 回填在线身份（songmid/hash/artwork/lyricsUrl）
class LocalMusicScraper {
  LocalMusicScraper(this._musicSourceService);

  static const _durationToleranceSeconds = 2;

  final MusicSourceService _musicSourceService;

  Future<ScrapeIdentity?> scrapeTrack(LocalTrack track) async {
    if (!track.hasEmbeddedTags) return null;
    final keyword = [
      track.artist,
      track.title,
      track.album,
    ].where((value) => value.trim().isNotEmpty).join(' ');
    try {
      final platformResults = await Future.wait(
        MusicSourceService.fallbackPlatforms.map(
          (platform) => _musicSourceService.builtInSources
              .search(platform, keyword, page: 1, limit: 10)
              .timeout(const Duration(seconds: 10))
              .catchError((_) => <MusicItem>[]),
        ),
      );
      final matches = [
        for (final results in platformResults)
          if (bestMatch(track, results) case final match?) match,
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
    final normalizedTitle = _normalize(track.title);
    final normalizedArtist = _normalize(track.artist);
    final normalizedAlbum = _normalize(track.album);
    final candidates = <({MusicItem song, int score})>[];
    for (final song in results) {
      if (_normalize(song.name) != normalizedTitle) continue;
      if (track.duration > Duration.zero) {
        final diff = (song.duration.inSeconds - track.duration.inSeconds).abs();
        if (diff > _durationToleranceSeconds) continue;
      }
      final songmid = song.songmid ?? song.hash;
      if (songmid == null || songmid.isEmpty) continue;
      var score = 0;
      if (normalizedArtist.isNotEmpty &&
          _normalize(song.singer).contains(normalizedArtist)) {
        score += 2;
      }
      if (normalizedAlbum.isNotEmpty &&
          _normalize(song.album).contains(normalizedAlbum)) {
        score++;
      }
      candidates.add((song: song, score: score));
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

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

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
}
