import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'lyric.dart';
import 'local_lyric_file.dart';
import '../data/lyric_parser.dart';
import '../../player/domain/music_item.dart';
import '../../../core/network/app_http_client.dart';
import '../../../core/network/music_source_service.dart';
import '../../../core/network/outbound_url.dart';
import '../../../core/storage/ttl_cache.dart';

typedef PreferredLyricLoader = Future<String?> Function(MusicItem music);

class LyricService {
  final Dio _dio;
  final MusicSourceService? _musicSourceService;
  final PreferredLyricLoader? _preferredLyricLoader;
  final TtlCache<Lyrics> _cache;

  LyricService([
    this._musicSourceService,
    TtlCache<Lyrics>? cache,
    Dio? dio,
    PreferredLyricLoader? preferredLyricLoader,
  ]) : _dio = dio ?? AppHttpClient.create(),
       _preferredLyricLoader = preferredLyricLoader,
       _cache = cache ?? TtlCache<Lyrics>(ttl: TtlCache.defaultTtl);

  Future<Lyrics> fetchLyric(MusicItem music) async {
    debugPrint(
      '[LyricService] fetchLyric: ${music.name}, platform=${music.platform}, songmid=${music.songmid}, source=${music.source}',
    );

    final cacheKey = _cacheKey(music);
    final localLyrics = music.meta?['localLyrics']?.toString();
    if (localLyrics != null && localLyrics.isNotEmpty) {
      final lyrics = _parseLyricString(localLyrics);
      _cache.set(cacheKey, lyrics);
      return lyrics;
    }
    final cached = _cache.get(cacheKey);
    if (cached != null && _hasWordTiming(cached)) {
      debugPrint('[LyricService] 命中缓存');
      return cached;
    }

    // 本地曲目旁边的同名 .lrc。放在缓存之后、网络之前：既避免每次播放都
    // 读盘，也不会为了一个本地文件去请求网络歌词（那通常是别家的错误匹配）。
    final sidecar = await _readSidecar(music);
    if (sidecar != null) {
      final lyrics = _parseLyricString(sidecar);
      if (lyrics.lines.isNotEmpty) {
        debugPrint('[LyricService] 使用同名歌词文件, ${lyrics.lines.length} 行');
        _cache.set(cacheKey, lyrics);
        return lyrics;
      }
    }

    if (_preferredLyricLoader != null || _musicSourceService != null) {
      try {
        debugPrint('[LyricService] 尝试从 MusicSourceService 获取歌词');
        final lyricStr =
            await (_preferredLyricLoader?.call(music) ??
                _musicSourceService!.getLyric(music));
        if (lyricStr != null && lyricStr.isNotEmpty) {
          final lyrics = _parseLyricString(lyricStr);
          debugPrint(
            '[LyricService] MusicSourceService 获取成功, ${lyrics.lines.length} 行',
          );
          _cache.set(cacheKey, lyrics);
          return lyrics;
        } else {
          debugPrint('[LyricService] MusicSourceService 返回空');
        }
      } catch (e) {
        debugPrint('[LyricService] MusicSourceService 获取失败: $e');
      }
    }

    // Built-in sources are attempted first because their lyric endpoint may
    // provide word timing while lyricsUrl is commonly only plain LRC.
    if (music.lyricsUrl != null && music.lyricsUrl!.isNotEmpty) {
      try {
        debugPrint('[LyricService] 尝试从 lyricsUrl 获取: ${music.lyricsUrl}');
        final response = await _dio.get(normalizeOutboundUrl(music.lyricsUrl!));
        if (response.statusCode == 200 && response.data is String) {
          final lyrics = _parseLyricString(response.data);
          debugPrint('[LyricService] lyricsUrl 获取成功, ${lyrics.lines.length} 行');
          _cache.set(cacheKey, lyrics);
          return lyrics;
        }
      } catch (e) {
        debugPrint('[LyricService] lyricsUrl 获取失败: $e');
      }
    }

    debugPrint('[LyricService] 所有途径均失败，返回空歌词');
    if (cached != null) return cached;
    return Lyrics.empty();
  }

  String _cacheKey(MusicItem music) {
    final platform = music.platform.isNotEmpty ? music.platform : music.source;
    final songId = music.songmid?.isNotEmpty == true
        ? music.songmid!
        : music.id;
    return '$platform|$songId|${music.id}';
  }

  bool _hasWordTiming(Lyrics lyrics) =>
      lyrics.lines.any((line) => line.hasWordTiming);

  /// 本地曲目的同名歌词文件。非本地来源一律返回 null。
  Future<String?> _readSidecar(MusicItem music) async {
    if (music.source != 'local') return null;
    final path = music.meta?['filePath']?.toString();
    if (path == null || path.isEmpty) return null;
    return readSidecarLyric(path);
  }

  void clearCache() {
    _cache.clear();
  }

  Lyrics _parseLyricString(String lyricStr) {
    // 有逐字标签时优先走能保留 words 的解析
    if (LyricParser.hasWordTiming(lyricStr)) {
      final hasLrcTimeTag =
          RegExp(r'\[\d{2}:\d{2}[\.\d]*\]').hasMatch(lyricStr) ||
          RegExp(r'^\[\d+\]', multiLine: true).hasMatch(lyricStr);
      if (hasLrcTimeTag) {
        // LRC + LRCX/QRC 字标签：parseLrc 已支持字级
        return LyricParser.parseLrc(lyricStr);
      }
      return LyricParser.parseQrc(lyricStr);
    }

    final hasLrcTimeTag =
        RegExp(r'\[\d{2}:\d{2}[\.\d]*\]').hasMatch(lyricStr) ||
        RegExp(r'^\[\d+\]', multiLine: true).hasMatch(lyricStr);
    if (hasLrcTimeTag) {
      return LyricParser.parseLrc(lyricStr);
    }
    return LyricParser.parseQrc(lyricStr);
  }

  Lyrics parseLrc(String lrc) => LyricParser.parseLrc(lrc);

  Lyrics parseQrc(String qrc) => LyricParser.parseQrc(qrc);

  void dispose() {
    _dio.close();
  }
}
