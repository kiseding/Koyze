import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../features/player/domain/music_item.dart';
import 'music_platform.dart';

/// 酷狗音乐匿名接口。全部走 HTTPS：`mobilecdn.kugou.com` 的证书不覆盖该
/// 域名，`mobiles.kugou.com` 是同一套 v3 接口的可用 HTTPS 入口。
const kugouSearchUrl = 'https://songsearch.kugou.com/song_search_v2';
const kugouLyricSearchUrl = 'https://lyrics.kugou.com/search';
const kugouLyricDownloadUrl = 'https://lyrics.kugou.com/download';
const kugouMobileApiBase = 'https://mobiles.kugou.com/api/v3';

const kugouWebUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const kugouMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// 酷狗图片 URL 用 `{size}` 占位，换成实际尺寸即可。
/// 同时把 http 升级到 https，避免 iOS ATS 与 Android 明文策略拦截。
String? kugouImageUrl(dynamic value, {int size = 1000}) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  var url = raw.replaceAll('{size}', '$size');
  if (url.startsWith('//')) url = 'https:$url';
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final secure = uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri;
  if (secure.scheme != 'https' && secure.scheme != 'http') return null;
  return secure.toString();
}

class _KgHashes {
  const _KgHashes({this.h128, this.h320, this.hflac});

  final String? h128;
  final String? h320;
  final String? hflac;
}

class KgSource extends MusicPlatform {
  @override
  String get id => 'kg';

  @override
  String get name => '酷狗音乐';

  late final Dio _dio;

  KgSource() {
    _dio = createDio();
    _dio.options.headers.addAll({
      'Referer': 'https://www.kugou.com/',
      'User-Agent': kugouWebUserAgent,
    });
  }

  Dio _mobileDio() => createDioForService(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        headers: {
          'User-Agent': kugouMobileUserAgent,
          'Referer': 'https://www.kugou.com/',
        },
      );

  // ---------------------------------------------------------------------------
  // 搜索
  // ---------------------------------------------------------------------------

  @override
  Future<List<MusicItem>> search(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _dio
          .get(
            kugouSearchUrl,
            queryParameters: {
              'keyword': keyword,
              'page': page.toString(),
              'pagesize': limit.toString(),
              'userid': '0',
              'clientver': '',
              'platform': 'WebFilter',
              'filter': '2',
              'iscorrection': '1',
              'privilege_filter': '0',
              'area_code': '1',
            },
          )
          .timeout(const Duration(seconds: 10));
      final body = _asMap(response.data);
      if (body == null) return [];
      clearFailure();
      return compute(_parseSearchPayload, body);
    } catch (e) {
      throw noteFailure('search', e);
    }
  }

  static List<MusicItem> _parseSearchPayload(Map<String, dynamic> body) {
    if (body['error_code'] != 0) return [];
    final data = body['data'];
    if (data is! Map) return [];
    final lists = data['lists'];
    if (lists is! List || lists.isEmpty) return [];

    final seen = <String>{};
    final items = <MusicItem>[];
    void add(dynamic raw) {
      if (raw is! Map) return;
      final map = Map<String, dynamic>.from(raw);
      final hash = (map['FileHash'] ?? map['hash'] ?? '').toString();
      if (hash.isEmpty || !seen.add(hash)) return;
      final parsed = parseKugouItem(map);
      if (parsed != null) items.add(parsed);
    }

    for (final raw in lists) {
      add(raw);
      if (raw is Map) {
        final group = raw['Grp'];
        if (group is List) {
          for (final child in group) {
            add(child);
          }
        }
      }
    }
    return items;
  }

  static MusicItem? parseKugouItem(Map<String, dynamic> raw) {
    final hashes = _hashesOf(raw);
    final hash = hashes.h128 ?? hashes.h320 ?? hashes.hflac;
    if (hash == null || hash.isEmpty) return null;

    final name = _titleOf(raw);
    if (name.isEmpty) return null;

    final singer = _singerOf(raw);
    final artwork = kugouImageUrl(
      raw['Image'] ?? raw['AlbumImage'] ?? raw['album_sizable_cover'] ?? raw['imgurl'],
    );

    return MusicItem(
      id: hash,
      name: name,
      singer: singer.isEmpty ? '未知歌手' : singer,
      album: (raw['AlbumName'] ?? raw['album_name'] ?? '').toString().trim(),
      duration: Duration(seconds: _intOf(raw['Duration'] ?? raw['duration'])),
      source: 'kg',
      platform: 'kg',
      artwork: artwork,
      url: '',
      songmid: (raw['Audioid'] ??
              raw['audio_id'] ??
              raw['album_audio_id'] ??
              raw['MixSongID'] ??
              '')
          .toString(),
      hash: hash,
      meta: {
        ...raw,
        if (hashes.h320 != null) 'kgHash320': hashes.h320,
        if (hashes.hflac != null) 'kgHashFlac': hashes.hflac,
        if (artwork != null) 'kgArtwork': artwork,
      },
    );
  }

  static _KgHashes _hashesOf(Map<String, dynamic> raw) {
    String read(List<String> keys) {
      for (final key in keys) {
        final value = raw[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    return _KgHashes(
      h128: read(['FileHash', 'hash']),
      h320: read(['HQFileHash', '320hash', 'hash_high']),
      hflac: read(['SQFileHash', 'sqhash']),
    );
  }

  static String _titleOf(Map<String, dynamic> raw) {
    final direct = (raw['SongName'] ?? raw['songname'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final filename = (raw['filename'] ?? raw['FileName'] ?? '').toString();
    final index = filename.indexOf(' - ');
    return (index >= 0 ? filename.substring(index + 3) : filename).trim();
  }

  static String _singerOf(Map<String, dynamic> raw) {
    final singers = raw['Singers'] ?? raw['authors'];
    if (singers is List) {
      final names = <String>[];
      for (final item in singers) {
        final name = item is Map
            ? (item['name'] ??
                    item['author_name'] ??
                    item['singername'] ??
                    '')
                .toString()
                .trim()
            : item?.toString().trim() ?? '';
        if (name.isNotEmpty) names.add(name);
      }
      if (names.isNotEmpty) return names.join('、');
    }
    final direct = (raw['singername'] ?? raw['author_name'] ?? '').toString();
    return direct.replaceAll('&', '、').trim();
  }

  static int _intOf(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return decoded is Map
            ? decoded.map((key, value) => MapEntry(key.toString(), value))
            : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  MusicItem parseItem(Map<String, dynamic> raw, String source) {
    return parseKugouItem(raw) ??
        MusicItem(id: '', name: '', singer: '', source: 'kg', platform: 'kg');
  }

  // ---------------------------------------------------------------------------
  // 歌词与封面
  // ---------------------------------------------------------------------------

  @override
  Future<String?> getLyric(MusicItem music) async {
    final hash = music.hash ?? music.songmid ?? music.id;
    if (hash.isEmpty) return null;
    try {
      final dio = createDioForService(
        headers: {
          'KG-RC': '1',
          'KG-THash': 'expand_search_manager.cpp:852736169:451',
          'User-Agent': 'KuGou2012-9020-ExpandSearchManager',
          'Referer': 'https://www.kugou.com/',
        },
      );
      final keyword = '${music.name} ${music.singer}'.trim();
      final search = await dio
          .get(
            kugouLyricSearchUrl,
            queryParameters: {
              'ver': '1',
              'man': 'yes',
              'client': 'pc',
              'keyword': keyword,
              'hash': hash,
              'timelength': music.duration.inMilliseconds.toString(),
            },
          )
          .timeout(const Duration(seconds: 10));
      final searchBody = _asMap(search.data);
      final candidates = searchBody?['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;

      final first = candidates.first;
      if (first is! Map) return null;
      final id = first['id']?.toString() ?? '';
      final accessKey = first['accesskey']?.toString() ?? '';
      if (id.isEmpty || accessKey.isEmpty) return null;

      final download = await dio
          .get(
            kugouLyricDownloadUrl,
            queryParameters: {
              'ver': '1',
              'client': 'pc',
              'id': id,
              'accesskey': accessKey,
              'fmt': 'lrc',
              'charset': 'utf8',
            },
          )
          .timeout(const Duration(seconds: 10));
      final downloadBody = _asMap(download.data);
      final content = downloadBody?['content']?.toString() ?? '';
      if (content.isEmpty) return null;
      final text = utf8.decode(base64Decode(content), allowMalformed: true);
      return text.isEmpty ? null : text;
    } catch (e) {
      noteFailure('lyric', e);
      return null;
    }
  }

  @override
  Future<String?> getArtwork(MusicItem music) async {
    // 只读搜索/榜单解析时写入的封面，不再调用任何播放信息接口。
    return kugouImageUrl((music.meta ?? const {})['kgArtwork']);
  }

  // ---------------------------------------------------------------------------
  // 榜单
  // ---------------------------------------------------------------------------

  static const _fallbackRankCategories = [
    LeaderboardCategory(id: 'kg:8888', name: 'TOP500', platform: 'kg'),
    LeaderboardCategory(id: 'kg:6666', name: '飙升榜', platform: 'kg'),
    LeaderboardCategory(id: 'kg:23784', name: '网络红歌榜', platform: 'kg'),
    LeaderboardCategory(id: 'kg:24971', name: 'DJ热歌榜', platform: 'kg'),
    LeaderboardCategory(id: 'kg:31308', name: '内地榜', platform: 'kg'),
    LeaderboardCategory(id: 'kg:33160', name: '电音榜', platform: 'kg'),
    LeaderboardCategory(id: 'kg:31310', name: '欧美榜', platform: 'kg'),
    LeaderboardCategory(id: 'kg:33165', name: '粤语金曲榜', platform: 'kg'),
  ];

  @override
  Future<List<LeaderboardCategory>> getLeaderboardCategories() async {
    try {
      final response = await _mobileDio()
          .get(
            '$kugouMobileApiBase/rank/list',
            queryParameters: {
              'parentid': '0',
              'withsong': '0',
              'with_res_tag': '0',
            },
          )
          .timeout(const Duration(seconds: 10));
      final body = _asMap(response.data);
      final data = body?['data'];
      final info = data is Map ? data['info'] : null;
      if (info is! List) return _fallbackRankCategories;

      final items = <LeaderboardCategory>[];
      for (final raw in info) {
        if (raw is! Map) continue;
        final id = (raw['rankid'] ?? raw['id'] ?? '').toString();
        final name = (raw['rankname'] ?? '').toString().trim();
        if (id.isEmpty || name.isEmpty) continue;
        items.add(
          LeaderboardCategory(
            id: 'kg:$id',
            name: name,
            platform: 'kg',
            coverUrl: kugouImageUrl(raw['imgurl'], size: 480),
          ),
        );
      }
      return items.isEmpty ? _fallbackRankCategories : items;
    } catch (e) {
      noteFailure('leaderboardCategories', e);
      return _fallbackRankCategories;
    }
  }

  @override
  Future<List<MusicItem>> getLeaderboardSongs(
    String leaderboardId, {
    int page = 1,
    int limit = 100,
  }) async {
    try {
      final parts = leaderboardId.split(':');
      final rankId = parts.length == 2 ? parts[1] : leaderboardId;
      final response = await _mobileDio()
          .get(
            '$kugouMobileApiBase/rank/song',
            queryParameters: {
              'version': '9108',
              'ranktype': '1',
              'plat': '0',
              'pagesize': limit.toString(),
              'area_code': '1',
              'page': page.toString(),
              'rankid': rankId,
              'with_res_tag': '0',
              'show_portrait_mv': '1',
            },
          )
          .timeout(const Duration(seconds: 12));
      final body = _asMap(response.data);
      if (body == null || body['errcode'] != 0) return [];
      final data = body['data'];
      final info = data is Map ? data['info'] : null;
      if (info is! List) return [];

      return info
          .whereType<Map>()
          .map((raw) => parseKugouItem(Map<String, dynamic>.from(raw)))
          .whereType<MusicItem>()
          .toList();
    } catch (e) {
      noteFailure('leaderboardSongs', e);
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // 歌单
  // ---------------------------------------------------------------------------

  @override
  Future<List<MusicItem>> searchSongLists(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _mobileDio()
          .get(
            '$kugouMobileApiBase/search/special',
            queryParameters: {
              'keyword': keyword,
              'page': page.toString(),
              'pagesize': limit.toString(),
              'version': '9108',
            },
          )
          .timeout(const Duration(seconds: 10));
      final body = _asMap(response.data);
      if (body == null || body['errcode'] != 0) return [];
      final data = body['data'];
      final info = data is Map ? data['info'] : null;
      if (info is! List) return [];

      return info.whereType<Map>().map((raw) {
        final map = Map<String, dynamic>.from(raw);
        return MusicItem(
          id: (map['specialid'] ?? '').toString(),
          name: (map['specialname'] ?? '').toString().trim(),
          singer: (map['nickname'] ?? '').toString().trim(),
          album: '${_intOf(map['songcount'])} 首',
          source: 'kg',
          platform: 'kg',
          artwork: kugouImageUrl(map['imgurl'], size: 480),
          isPlayable: false,
        );
      }).where((item) => item.id.isNotEmpty).toList();
    } catch (e) {
      noteFailure('searchSongLists', e);
      return [];
    }
  }

  @override
  Future<List<MusicItem>> getSongListDetail(
    String songListId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final id = songListId.split(':').last;
      final response = await _mobileDio()
          .get(
            '$kugouMobileApiBase/special/song',
            queryParameters: {
              'specialid': id,
              'page': page.toString(),
              'pagesize': limit.toString(),
              'version': '9108',
              'plat': '0',
              'area_code': '1',
            },
          )
          .timeout(const Duration(seconds: 12));
      final body = _asMap(response.data);
      if (body == null || body['errcode'] != 0) return [];
      final data = body['data'];
      final info = data is Map ? data['info'] : null;
      if (info is! List) return [];

      return info
          .whereType<Map>()
          .map((raw) => parseKugouItem(Map<String, dynamic>.from(raw)))
          .whereType<MusicItem>()
          .toList();
    } catch (e) {
      noteFailure('songListDetail', e);
      return [];
    }
  }

  void dispose() {
    _dio.close();
    closeReusedServiceClients();
  }
}
