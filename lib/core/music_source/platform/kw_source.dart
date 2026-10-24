import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../features/player/domain/music_item.dart';
import 'music_platform.dart';
import 'source_utils.dart';
import 'wbd_crypto.dart';

const kuwoSearchBaseUrl = 'https://search.kuwo.cn';
const kuwoArtworkEndpoint = 'https://artistpicserver.kuwo.cn/pic.web';
const kuwoLyricEndpoint = 'https://newlyric.kuwo.cn/newlyric.lrc';
const kuwoPlaylistEndpoint = 'https://nplserver.kuwo.cn/pl.svc';

class KwSource extends MusicPlatform {
  @override
  String get id => 'kw';

  @override
  String get name => '酷我音乐';

  late final Dio _dio;

  KwSource() {
    _dio = createDio();
    _dio.options.baseUrl = kuwoSearchBaseUrl;
    _dio.options.headers.addAll({
      'Referer': 'https://www.kuwo.cn/',
      'Cookie': 'kw_token=',
    });
  }

  @override
  Future<List<MusicItem>> search(String keyword,
      {int page = 1, int limit = 20}) async {
    try {
      final response = await _dio.get(
        '/r.s',
        queryParameters: {
          'client': 'kt',
          'all': keyword,
          'pn': (page - 1).toString(),
          'rn': limit.toString(),
          'uid': '794762570',
          'ver': 'kwplayer_ar_9.2.2.1',
          'vipver': '1',
          'show_copyright_off': '1',
          'newver': '1',
          'ft': 'music',
          'cluster': '0',
          'strategy': '2012',
          'encoding': 'utf8',
          'rformat': 'json',
          'vermerge': '1',
          'mobi': '1',
          'issubtitle': '1',
        },
      ).timeout(const Duration(seconds: 10));

      final data = response.data;
      if (data == null) return [];

      // 使用 compute 在后台线程解析，防止 UI 卡顿
      final results = await compute(_parseSearchResult, data);
      clearFailure();
      return results;
    } catch (e) {
      throw noteFailure('search', e);
    }
  }

  static List<MusicItem> _parseSearchResult(dynamic data) {
    final body = data is Map<String, dynamic>
        ? data
        : (data is String ? jsonDecode(data) : null);
    if (body == null) return [];

    final abslist = body['abslist'] as List<dynamic>?;
    if (abslist == null || abslist.isEmpty) return [];

    final list = <MusicItem>[];
    for (final item in abslist) {
      final parsed = _staticParseItem(item as Map<String, dynamic>);
      if (parsed != null) list.add(parsed);
    }
    return list;
  }

  static MusicItem? _staticParseItem(Map<String, dynamic> item) {
    // 支持搜索 API（大写字段）和排行榜 API（小写字段）
    // 搜索 API: MUSICRID (格式: MUSIC_12345)
    // 排行榜 API: id (纯数字)
    String songmid;
    final musicRid = item['MUSICRID'] as String? ?? item['rid'] as String?;
    if (musicRid != null) {
      songmid = musicRid.replaceAll('MUSIC_', '');
    } else {
      // 排行榜 API 使用 id 字段
      songmid = item['id']?.toString() ?? '';
    }
    if (songmid.isEmpty) return null;

    final duration = int.tryParse(item['DURATION']?.toString() ??
            item['duration']?.toString() ??
            '') ??
        0;

    final artwork = normalizeKuwoArtwork(item);

    return MusicItem(
      id: songmid,
      name:
          (item['SONGNAME'] as String? ?? item['name'] as String? ?? '').trim(),
      singer: (item['ARTIST'] as String? ?? item['artist'] as String? ?? '')
          .replaceAll('&', '、'),
      source: 'kw',
      platform: 'kw',
      artwork: artwork,
      url: '',
      songmid: songmid,
      hash: songmid,
      duration: Duration(seconds: duration),
      album:
          (item['ALBUM'] as String? ?? item['album'] as String? ?? '').trim(),
      // 保留 MUSICRID、rid、formats 等字段，供自定义源按平台协议解析。
      meta: Map<String, dynamic>.from(item),
    );
  }

  Map<String, dynamic>? _jsonDecode(String data) {
    try {
      return jsonDecode(data) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  MusicItem? _parseSearchItem(Map<String, dynamic> item) {
    return _staticParseItem(item);
  }

  @override
  Future<String?> getArtwork(MusicItem music) async {
    final rid = music.songmid ?? music.id;
    if (rid.isEmpty) return null;

    try {
      final response = await _dio.get(
        kuwoArtworkEndpoint,
        queryParameters: {
          'corp': 'kuwo',
          'type': 'rid_pic',
          'pictype': '500',
          'size': '500',
          'rid': rid,
        },
      ).timeout(const Duration(seconds: 5));

      final url = response.data?.toString().trim() ?? '';
      if (url.startsWith('http')) {
        return normalizeNeteaseArtwork(url);
      }
      return null;
    } catch (e) {
      noteFailure('artwork', e);
      return null;
    }
  }

  @override
  Future<String?> getLyric(MusicItem music) async {
    try {
      final songmid = music.songmid ?? music.id;
      if (songmid.isEmpty) {
        debugPrint('[KW] getLyric: songmid 为空');
        return null;
      }

      debugPrint('[KW] getLyric: songmid=$songmid');
      final params = kwBuildParams(songmid, true);
      final lyricDio = createDioForService(
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
          'Referer': 'https://www.kuwo.cn/',
        },
      );
      final response = await lyricDio.get(
        '$kuwoLyricEndpoint?$params',
        options: Options(responseType: ResponseType.bytes),
      );

      final data = response.data;
      if (data is! List) {
        debugPrint('[KW] getLyric: 响应不是 List, type=${data.runtimeType}');
        return null;
      }

      final result = kwDecodeResponse(data.cast<int>(), true);
      debugPrint('[KW] getLyric: 解码成功, length=${result?.length ?? 0}');
      return result;
    } catch (e) {
      debugPrint('[KW] getLyric 失败: $e');
      return null;
    }
  }

  @override
  MusicItem parseItem(Map<String, dynamic> raw, String source) {
    return _parseSearchItem(raw) ??
        MusicItem(id: '', name: '', singer: '', source: 'kw', platform: 'kw');
  }

  @override
  Future<List<MusicItem>> searchSongLists(String keyword,
      {int page = 1, int limit = 20}) async {
    try {
      final response = await _dio.get(
        '/r.s',
        queryParameters: {
          'client': 'kt',
          'all': keyword,
          'pn': (page - 1).toString(),
          'rn': limit.toString(),
          'ft': 'songlist',
          'cluster': '0',
          'strategy': '2012',
          'encoding': 'utf8',
          'rformat': 'json',
          'vermerge': '1',
          'mobi': '1',
        },
      ).timeout(const Duration(seconds: 10));

      final data = response.data;
      if (data == null) return [];
      final body = data is Map<String, dynamic>
          ? data
          : (data is String ? _jsonDecode(data) : null);
      if (body == null) return [];

      final abslist = body['abslist'] as List<dynamic>?;
      if (abslist == null) return [];

      return abslist
          .map((item) {
            final m = item as Map<String, dynamic>;
            return MusicItem(
              id: (m['playlistid'] ?? m['DC_TARGETID'] ?? '').toString(),
              name: (m['name'] ?? m['SONGNAME'] ?? '').toString().trim(),
              singer: (m['nickname'] ?? m['ARTIST'] ?? '').toString().trim(),
              source: 'kw',
              platform: 'kw',
              artwork: normalizeKuwoArtwork(m),
              album: '${(m['songnum'] ?? 0)} 首',
              isPlayable: false,
            );
          })
          .where((m) => m.id.isNotEmpty)
          .toList();
    } catch (e) {
      noteFailure('searchSongLists', e);
      return [];
    }
  }

  @override
  Future<List<MusicItem>> getSongListDetail(String songListId,
      {int page = 1, int limit = 50}) async {
    try {
      final dio = createDioForService(headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
        'Referer': 'https://www.kuwo.cn/',
      });
      final response = await dio.get(
        kuwoPlaylistEndpoint,
        queryParameters: {
          'op': 'getlistinfo',
          'pid': songListId,
          'pn': (page - 1).toString(),
          'rn': limit.toString(),
          'encode': 'utf8',
          'keyset': 'pl2012',
          'identity': 'kuwo',
          'pcjson': '1',
        },
      ).timeout(const Duration(seconds: 10));

      final data = response.data;
      if (data == null) return [];
      final body = data is Map<String, dynamic>
          ? data
          : (data is String ? _jsonDecode(data) : null);
      if (body == null) return [];

      final musiclist = body['musiclist'] as List<dynamic>?;
      if (musiclist == null) return [];

      return musiclist
          .map((item) => _staticParseItem(item as Map<String, dynamic>))
          .whereType<MusicItem>()
          .toList();
    } catch (e) {
      noteFailure('songListDetail', e);
      return [];
    }
  }

  @override
  Future<List<LeaderboardCategory>> getLeaderboardCategories() async {
    final fallback = const [
      LeaderboardCategory(id: 'kw:93', name: '飙升榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:17', name: '新歌榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:16', name: '热歌榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:158', name: '抖音热歌榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:292', name: '铃声榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:284', name: '热评榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:290', name: 'ACG新歌榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:286', name: '台湾KKBOX榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:279', name: '冬日暖心榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:281', name: '巴士随身听榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:255', name: 'KTV点唱榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:280', name: '家务进行曲榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:282', name: '熬夜修仙榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:283', name: '枕边轻音乐榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:278', name: '古风音乐榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:264', name: 'Vlog音乐榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:242', name: '电音榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:187', name: '流行趋势榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:204', name: '现场音乐榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:186', name: 'ACG神曲榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:185', name: '最强翻唱榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:26', name: '经典怀旧榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:104', name: '华语榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:182', name: '粤语榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:22', name: '欧美榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:184', name: '韩语榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:183', name: '日语榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:145', name: '会员畅听榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:153', name: '网红新歌榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:64', name: '影视金曲榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:176', name: 'DJ嗨歌榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:106', name: '真声音', platform: 'kw'),
      LeaderboardCategory(id: 'kw:12', name: 'Billboard榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:49', name: 'iTunes音乐榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:180', name: 'beatport电音榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:13', name: '英国UK榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:164', name: '百大DJ榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:246', name: 'YouTube音乐排行榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:265', name: '韩国Genie榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:14', name: '韩国M-net榜', platform: 'kw'),
      LeaderboardCategory(id: 'kw:8', name: '香港电台中文歌曲龙虎榜', platform: 'kw'),
    ];

    // 只返回静态分类，不再为每个榜拉首曲取封面。
    // 41 个榜 × 6 路并发 = 至少 7 轮请求，而调用方（榜单页）给整个平台的
    // 超时只有 12 秒，几乎必然超时被当成空列表——酷我整段榜单由此消失，
    // 残缺结果还会覆盖缓存。封面改由消费方按需取（榜单页用热歌榜首曲）。
    return fallback;
  }

  @override
  Future<List<MusicItem>> getLeaderboardSongs(String leaderboardId,
      {int page = 1, int limit = 100}) async {
    try {
      final parts = leaderboardId.split(':');
      final bangid = parts.length == 2 ? parts[1] : leaderboardId;

      debugPrint('[KW] getLeaderboardSongs: bangid=$bangid, page=$page');

      // 桌面版使用的 API: https://wbd.kuwo.cn/api/bd/bang/bang_info
      final requestBody = {
        'uid': '',
        'devId': '',
        'sFrom': 'kuwo_sdk',
        'user_type': 'AP',
        'carSource': 'kwplayercar_ar_6.0.1.0_apk_keluze.apk',
        'id': bangid,
        'pn': page - 1,
        'rn': limit,
      };

      final url =
          'https://wbd.kuwo.cn/api/bd/bang/bang_info?${WbdCrypto.buildParam(requestBody)}';
      debugPrint('[KW] Request completed');

      final response = await _dio
          .get(
            url,
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(seconds: 10));

      final data = response.data;
      debugPrint('[KW] Response status: ${response.statusCode}');
      debugPrint('[KW] Response type: ${data.runtimeType}');
      debugPrint(
          '[KW] Response data (first 500 chars): ${data.toString().substring(0, data.toString().length > 500 ? 500 : data.toString().length)}');

      // API 返回 base64 编码的加密数据（text/plain），Dio 返回 String
      String base64Result;
      if (data is String) {
        base64Result = data;
      } else if (data is Map) {
        base64Result = data['data']?.toString() ?? '';
      } else {
        debugPrint('[KW] getLeaderboardSongs: unexpected type');
        return [];
      }

      if (base64Result.isEmpty) {
        debugPrint('[KW] getLeaderboardSongs: empty data');
        return [];
      }

      debugPrint('[KW] Decoding base64 data...');
      final decrypted = WbdCrypto.decodeData(base64Result);
      debugPrint(
          '[KW] Decrypted data (first 500 chars): ${decrypted.substring(0, decrypted.length > 500 ? 500 : decrypted.length)}');

      final bodyMap = jsonDecode(decrypted) as Map<String, dynamic>;
      debugPrint('[KW] Parsed JSON code: ${bodyMap['code']}');

      if (bodyMap['code'] != 200) {
        debugPrint('[KW] getLeaderboardSongs: code=${bodyMap['code']}');
        return [];
      }

      final musiclist = bodyMap['data']?['musiclist'] as List<dynamic>?;
      if (musiclist == null) {
        debugPrint('[KW] getLeaderboardSongs: no musiclist');
        debugPrint('[KW] data keys: ${bodyMap['data']?.keys}');
        return [];
      }

      debugPrint('[KW] getLeaderboardSongs: ${musiclist.length} songs');
      if (musiclist.isNotEmpty) {
        debugPrint('[KW] First song: ${musiclist[0]}');
      }

      return musiclist
          .map((item) => _staticParseItem(item as Map<String, dynamic>))
          .whereType<MusicItem>()
          .toList();
    } catch (e) {
      debugPrint('[KW] getLeaderboardSongs error: $e');
      return [];
    }
  }

  void dispose() {
    _dio.close();
    closeReusedServiceClients();
  }

}
