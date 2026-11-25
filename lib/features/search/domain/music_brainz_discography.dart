import 'dart:async';

import 'package:dio/dio.dart';

import '../../player/domain/music_item.dart';

/// MusicBrainz 的公开 Web 服务：无需 API key，但要求客户端平均不超过
/// 每秒一次请求（官方 Rate limiting 条款）。所有请求都要经过 [MBRequestGate]，
/// 避免歌手页并发打开时把请求叠在一起被返回 429。
const String musicBrainzBaseUrl = 'https://musicbrainz.org/ws/2';

/// MusicBrainz 要求带可识别的 User-Agent，否则可能直接拒绝。
const String musicBrainzUserAgent =
    'Koyze/6.0 (https://github.com/kiseding/koyze)';

/// 一张专辑/单曲/EP 的发行信息。
///
/// [firstReleaseDate] 可能只有年份（`1999`）或年月（`1999-05`），
/// 与 MusicBrainz 的 `first-release-date` 原样一致。
class MusicBrainzRelease {
  const MusicBrainzRelease({
    required this.title,
    required this.firstReleaseDate,
  });

  final String title;
  final String firstReleaseDate;

  /// 专辑名匹配用的归一化键。
  String get titleKey => normalizeMusicBrainzName(title);
}

/// 串行化 + 最小间隔的请求闸门。
///
/// 同一时刻只允许一个请求在途，且相邻两次请求开始时间至少间隔
/// [minInterval]，从而满足 MusicBrainz 的平均速率要求。
class MBRequestGate {
  MBRequestGate({
    this.minInterval = const Duration(milliseconds: 1100),
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final Duration minInterval;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();
  DateTime? _lastStart;

  Future<T> run<T>(Future<T> Function() task) {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    return () async {
      await previous;
      try {
        final last = _lastStart;
        if (last != null) {
          final elapsed = _clock().difference(last);
          if (elapsed < minInterval) {
            await _sleep(minInterval - elapsed);
          }
        }
        _lastStart = _clock();
        return await task();
      } finally {
        completer.complete();
      }
    }();
  }
}

/// 按歌手名查询发行目录，并在进程内缓存结果。
///
/// 一次歌手页只应该产生一次网络往返：命中缓存或已有在途请求时直接复用。
/// 任何失败都降级为空列表，绝不抛出到 UI。
class MusicBrainzDiscography {
  MusicBrainzDiscography(
    this._dio, {
    MBRequestGate? gate,
    this.pageSize = 100,
    this.maxPages = 2,
    this.cacheTtl = const Duration(hours: 12),
    DateTime Function()? clock,
  }) : _gate = gate ?? MBRequestGate(),
       _clock = clock ?? DateTime.now;

  final Dio _dio;
  final MBRequestGate _gate;
  final int pageSize;
  final int maxPages;
  final Duration cacheTtl;
  final DateTime Function() _clock;

  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  Future<List<MusicBrainzRelease>> releasesFor(String artistName) {
    final key = normalizeMusicBrainzName(artistName);
    if (key.isEmpty) return Future<List<MusicBrainzRelease>>.value(const []);

    final cached = _cache[key];
    if (cached != null && !cached.isStale(_clock(), cacheTtl)) {
      return cached.future;
    }

    final future = _load(artistName);
    // 失败也缓存一小段时间，避免每次进页面都重试拖慢加载；
    // 由 _load 内部保证不抛异常。
    _cache[key] = _CacheEntry(future, _clock());
    return future;
  }

  Future<List<MusicBrainzRelease>> _load(String artistName) async {
    try {
      final mbid = await _lookupArtistId(artistName);
      if (mbid == null) return const [];
      return await _browseReleases(mbid);
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _lookupArtistId(String artistName) async {
    final data = await _gate.run(() async {
      final response = await _dio.get<dynamic>(
        '$musicBrainzBaseUrl/artist/',
        queryParameters: {
          'query': 'artist:"${_sanitizeQuery(artistName)}"',
          'fmt': 'json',
          'limit': 5,
        },
      );
      return response.data;
    });
    if (data is! Map || data['artists'] is! List) return null;

    final wanted = normalizeMusicBrainzName(artistName);
    Map<dynamic, dynamic>? best;
    var bestScore = -1;
    for (final candidate in (data['artists'] as List).whereType<Map>()) {
      final name = normalizeMusicBrainzName(
        candidate['name']?.toString() ?? '',
      );
      final score = int.tryParse(candidate['score']?.toString() ?? '') ?? 0;
      if (name == wanted && score >= 0) {
        final id = candidate['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    // 名称不完全一致（例如 "周杰伦" vs "Jay Chou" 的别名）时，
    // 只在 MusicBrainz 给出 90 分以上高置信度时才采用首条结果。
    if (bestScore >= 90) {
      final id = best?['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  Future<List<MusicBrainzRelease>> _browseReleases(String mbid) async {
    final releases = <MusicBrainzRelease>[];
    var offset = 0;
    for (var page = 0; page < maxPages; page++) {
      final data = await _gate.run(() async {
        final response = await _dio.get<dynamic>(
          '$musicBrainzBaseUrl/release-group',
          queryParameters: {
            'artist': mbid,
            'fmt': 'json',
            'limit': pageSize,
            'offset': offset,
          },
        );
        return response.data;
      });
      if (data is! Map || data['release-groups'] is! List) break;
      final batch = (data['release-groups'] as List).whereType<Map>().toList(
        growable: false,
      );
      for (final album in batch) {
        final title = album['title']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        releases.add(
          MusicBrainzRelease(
            title: title,
            firstReleaseDate:
                album['first-release-date']?.toString().trim() ?? '',
          ),
        );
      }
      if (batch.length < pageSize) break;
      offset += batch.length;
    }
    return releases;
  }

  /// 测试与手动刷新用：清空缓存。
  void clearCache() => _cache.clear();
}

class _CacheEntry {
  _CacheEntry(this.future, this.createdAt);

  final Future<List<MusicBrainzRelease>> future;
  final DateTime createdAt;

  bool isStale(DateTime now, Duration ttl) => now.difference(createdAt) > ttl;
}

/// MusicBrainz 的 Lucene 查询里引号与反斜杠需要转义，否则歌手名带引号会拼坏语法。
String _sanitizeQuery(String value) =>
    value.replaceAll('\\', ' ').replaceAll('"', ' ').trim();

/// 归一化歌手名/专辑名：大小写、空白、引号与常见标点不参与比较。
String normalizeMusicBrainzName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\u3000\-_.!,?()（）【】\[\]「」『』:：·&/]'), '')
    .replaceAll(RegExp(r'["\u2018\u2019\u201C\u201D]'), '');

/// 把发行年份写回歌曲 meta，供 `artist_albums.dart` 的专辑排序使用。
///
/// 只做精确专辑名匹配：宁可少补年份，也不要把别的专辑的时间套上来。
List<MusicItem> applyMusicBrainzReleaseDates(
  List<MusicItem> songs,
  List<MusicBrainzRelease> releases,
) {
  if (songs.isEmpty || releases.isEmpty) return songs;
  final byKey = <String, String>{};
  for (final release in releases) {
    final key = release.titleKey;
    if (key.isEmpty || release.firstReleaseDate.isEmpty) continue;
    // 同名专辑（不同版本）取最早发行的那个年份。
    final existing = byKey[key];
    if (existing == null || release.firstReleaseDate.compareTo(existing) < 0) {
      byKey[key] = release.firstReleaseDate;
    }
  }
  if (byKey.isEmpty) return songs;

  var changed = false;
  final result = songs
      .map((song) {
        final key = normalizeMusicBrainzName(song.album);
        final date = byKey[key];
        if (date == null) return song;
        final meta = Map<String, dynamic>.from(song.meta ?? const {});
        if (meta['musicBrainzReleaseDate'] == date) return song;
        meta['musicBrainzReleaseDate'] = date;
        changed = true;
        return song.copyWith(meta: meta);
      })
      .toList(growable: false);
  return changed ? result : songs;
}
