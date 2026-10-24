import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../features/player/domain/music_item.dart';
import 'music_platform.dart';
import 'qrc_decoder.dart';

class TxSource extends MusicPlatform {
  @override
  String get id => 'tx';

  @override
  String get name => 'QQ音乐';

  late final Dio _dio;

  TxSource() {
    _dio = createDio();
    _dio.options.baseUrl = 'https://u.y.qq.com';
    _dio.options.headers.addAll({
      'User-Agent': 'QQMusic 14090508(android 12)',
    });
  }

  @override
  Future<List<MusicItem>> search(String keyword,
      {int page = 1, int limit = 20}) async {
    try {
      final response = await _dio.get(
        'https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp',
        options: Options(headers: {'Referer': 'https://y.qq.com/'}),
        queryParameters: {
          'w': keyword,
          'format': 'json',
          'p': page.toString(),
          'n': limit.toString(),
          'cr': '1',
          'aggr': '1',
          'lossless': '1',
          'platform': 'h5',
          'g_tk': '5381',
        },
      ).timeout(const Duration(seconds: 10));

      final data = response.data;
      if (data == null) return [];

      final results = await compute(_parseSearchResult, data);
      clearFailure();
      return results;
    } catch (e) {
      throw noteFailure('search', e);
    }
  }

  static List<MusicItem> _parseSearchResult(dynamic data) {
    final body = data is String ? jsonDecode(data) : data;
    if (body is! Map) return [];

    final song = body['data']?['song'];
    if (song is! Map) return [];

    final list = song['list'] as List<dynamic>?;
    if (list == null || list.isEmpty) return [];

    return _staticHandleResult(list);
  }

  static List<MusicItem> _staticHandleResult(List<dynamic> rawList) {
    final list = <MusicItem>[];
    for (final item in rawList) {
      final map = item as Map<String, dynamic>;

      final songmid = map['songmid'] as String? ?? '';
      if (songmid.isEmpty) continue;

      final singerList = map['singer'] as List<dynamic>? ?? [];
      final albumName = map['albumname'] as String? ?? '';
      final albumMid = map['albummid'] as String? ?? '';
      final interval = int.tryParse(map['interval']?.toString() ?? '0') ?? 0;

      list.add(MusicItem(
        id: songmid,
        name: (map['songname'] as String? ?? '').trim(),
        singer: _staticFormatSingerName(singerList, nameKey: 'name'),
        source: 'tx',
        platform: 'tx',
        artwork: albumMid.isNotEmpty && albumMid != '空'
            ? 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg'
            : '',
        url: '',
        songmid: songmid,
        duration: Duration(seconds: interval),
        album: albumName,
        // 自定义洛雪源会读取 strMediaMid、file、pay 等平台原始字段来签发 URL。
        meta: Map<String, dynamic>.from(map),
      ));
    }
    return list;
  }

  static String _staticFormatSingerName(List<dynamic> singers,
      {String nameKey = 'name'}) {
    if (singers.isEmpty) return '未知歌手';
    return singers
        .map((s) => (s as Map)[nameKey]?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .join('、');
  }

  List<MusicItem> _handleResult(List<dynamic> rawList) {
    return _staticHandleResult(rawList);
  }

  @override
  Future<String?> getLyric(MusicItem music) async {
    try {
      final qrc = await _getQrcLyric(music);
      if (qrc != null && qrc.isNotEmpty) return qrc;
    } catch (e) {
      debugPrint('[TX] QRC lyric failed: $e');
    }
    return _getLegacyLyric(music);
  }

  Future<String?> _getQrcLyric(MusicItem music) async {
    final songmid = music.songmid ?? music.id;
    if (songmid.isEmpty) return null;

    final songId = await _getSongId(songmid);
    if (songId == null) return null;

    final lyricDio = createDioForService(
      headers: {'Referer': 'https://y.qq.com'},
    );
    final resp = await lyricDio.post(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: {
        'comm': {
          'ct': '19',
          'cv': '1859',
          'uin': '0',
        },
        'req': {
          'method': 'GetPlayLyricInfo',
          'module': 'music.musichallSong.PlayLyricInfo',
          'param': {
            'format': 'json',
            'crypt': 1,
            'ct': 19,
            'cv': 1873,
            'interval': 0,
            'lrc_t': 0,
            'qrc': 1,
            'qrc_t': 0,
            'roma': 1,
            'roma_t': 0,
            'songID': songId,
            'trans': 1,
            'trans_t': 0,
            'type': -1,
          },
        },
      },
    );

    final rawData = resp.data;
    final body = rawData is String ? jsonDecode(rawData) : rawData;
    if (body is! Map) return null;
    if (body['code'] != 0) return null;

    final req = body['req'];
    if (req is! Map || req['code'] != 0) return null;
    final data = req['data'];
    if (data is! Map) return null;

    final hex = data['lyric']?.toString();
    if (hex == null || hex.isEmpty) return null;
    return decryptQrc(hex);
  }

  Future<int?> _getSongId(String songmid) async {
    final dio = createDioForService(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)'
      },
    );
    final resp = await dio.post(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: {
        'comm': {
          'ct': '19',
          'cv': '1859',
          'uin': '0',
        },
        'req': {
          'module': 'music.pf_song_detail_svr',
          'method': 'get_song_detail_yqq',
          'param': {
            'song_type': 0,
            'song_mid': songmid,
          },
        },
      },
    );

    final rawData = resp.data;
    final body = rawData is String ? jsonDecode(rawData) : rawData;
    if (body is! Map) return null;
    final trackInfo = body['req']?['data']?['track_info'];
    if (trackInfo is! Map) return null;
    final id = trackInfo['id'];
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '');
  }

  Future<String?> _getLegacyLyric(MusicItem music) async {
    try {
      final songmid = music.songmid ?? music.id;
      if (songmid.isEmpty) return null;

      final lyricDio =
          createDioForService(headers: {'Referer': 'https://y.qq.com/'});

      final resp = await lyricDio.get(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
        queryParameters: {
          'songmid': songmid,
          'format': 'json',
          'platform': 'h5',
        },
      );

      final rawData = resp.data;
      final body = rawData is String ? jsonDecode(rawData) : rawData;
      if (body is! Map) return null;

      final lyricBase64 = body['lyric'] as String?;
      if (lyricBase64 == null || lyricBase64.isEmpty) return null;

      return utf8.decode(base64Decode(lyricBase64));
    } catch (e) {
      noteFailure('lyric', e);
      return null;
    }
  }

  @override
  MusicItem parseItem(Map<String, dynamic> raw, String source) {
    final list = _handleResult([raw]);
    return list.isNotEmpty
        ? list.first
        : MusicItem(id: '', name: '', singer: '', source: 'tx', platform: 'tx');
  }

  @override
  Future<List<LeaderboardCategory>> getLeaderboardCategories() async {
    final base = const [
      LeaderboardCategory(id: 'tx:4', name: '流行指数榜', platform: 'tx'),
      LeaderboardCategory(id: 'tx:26', name: '热歌榜', platform: 'tx'),
      LeaderboardCategory(id: 'tx:27', name: '新歌榜', platform: 'tx'),
      LeaderboardCategory(id: 'tx:62', name: '飙升榜', platform: 'tx'),
      LeaderboardCategory(id: 'tx:28', name: '网络歌曲榜', platform: 'tx'),
      LeaderboardCategory(id: 'tx:5', name: '内地榜', platform: 'tx'),
      LeaderboardCategory(id: 'tx:3', name: '欧美榜', platform: 'tx'),
      LeaderboardCategory(id: 'tx:16', name: '韩国榜', platform: 'tx'),
    ];
    // 分类接口只返回静态分类：为 8 个榜各拉一次歌曲只为了拿一张封面，
    // 首屏要多等 8 个请求，封面由消费方按需取（榜单页用热歌榜首曲）。
    return base;
  }

  @override
  Future<List<MusicItem>> getLeaderboardSongs(String leaderboardId,
      {int page = 1, int limit = 100}) async {
    try {
      final parts = leaderboardId.split(':');
      final topid = int.parse(parts.length == 2 ? parts[1] : leaderboardId);

      debugPrint('[TX] getLeaderboardSongs: topid=$topid');

      // 桌面版使用 POST + JSON body
      final response = await _dio.post(
        'https://u.y.qq.com/cgi-bin/musicu.fcg',
        data: {
          'toplist': {
            'module': 'musicToplist.ToplistInfoServer',
            'method': 'GetDetail',
            'param': {
              'topid': topid,
              'num': limit,
              'period': '',
            },
          },
          'comm': {
            'uin': 0,
            'format': 'json',
            'ct': 20,
            'cv': 1859,
          },
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
          },
        ),
      );

      final body = response.data;
      debugPrint('[TX] getLeaderboardSongs response: ${body.runtimeType}');

      Map<String, dynamic> bodyMap;
      if (body is Map) {
        bodyMap = body.map((k, v) => MapEntry(k.toString(), v));
      } else if (body is String) {
        try {
          var jsonStr = body;
          final callbackIdx = jsonStr.indexOf('(');
          if (callbackIdx != -1 && jsonStr.endsWith(')')) {
            jsonStr = jsonStr.substring(callbackIdx + 1, jsonStr.length - 1);
          }
          bodyMap = (jsonDecode(jsonStr) as Map)
              .map((k, v) => MapEntry(k.toString(), v));
        } catch (e) {
          debugPrint('[TX] getLeaderboardSongs: jsonDecode failed: $e');
          debugPrint(
              '[TX] response preview: ${body.toString().substring(0, body.toString().length > 300 ? 300 : body.toString().length)}');
          return [];
        }
      } else {
        debugPrint('[TX] getLeaderboardSongs: unexpected type');
        return [];
      }

      if (bodyMap['code'] != 0) {
        debugPrint('[TX] getLeaderboardSongs: code=${bodyMap['code']}');
        return [];
      }

      final songList =
          bodyMap['toplist']?['data']?['songInfoList'] as List<dynamic>?;
      if (songList == null) {
        debugPrint('[TX] getLeaderboardSongs: no songInfoList');
        debugPrint('[TX] toplist keys: ${bodyMap['toplist']?.keys}');
        return [];
      }

      debugPrint('[TX] getLeaderboardSongs: ${songList.length} songs');

      return songList
          .map((item) => _parseItem(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[TX] getLeaderboardSongs error: $e');
      return [];
    }
  }

  MusicItem _parseItem(Map<String, dynamic> item) {
    final singer = item['singer'] as List<dynamic>?;
    final singerName = singer?.map((s) => s['name'] as String).join('、') ?? '';

    final file = item['file'] as Map<String, dynamic>?;
    final albumName = item['album']?['name'] as String? ?? '';
    final albumMid = item['album']?['mid'] as String? ?? '';

    // 桌面版: 专辑名为空时用歌手封面
    String artwork;
    if (albumName.isEmpty || albumName == '空') {
      final singerMid = (singer != null && singer.isNotEmpty)
          ? singer[0]['mid'] as String? ?? ''
          : '';
      artwork = singerMid.isNotEmpty
          ? 'https://y.gtimg.cn/music/photo_new/T001R500x500M000$singerMid.jpg'
          : '';
    } else {
      artwork =
          'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg';
    }

    // songmid 必须是歌曲 mid。
    // 勿把 file.media_mid 写入 hash：自定义源（如聆澜）常用
    //   songId = musicInfo.hash ?? musicInfo.songmid
    // media_mid 是文件 ID，会解析出无效地址 http://wx.music.tc.qq.com/
    final songmid = item['mid']?.toString() ?? '';
    final mediaMid = file?['media_mid']?.toString() ?? '';
    return MusicItem(
      id: songmid,
      name: item['title'] as String? ?? '',
      singer: singerName,
      album: albumName,
      duration: Duration(seconds: item['interval'] as int? ?? 0),
      source: 'tx',
      platform: 'tx',
      songmid: songmid,
      hash: null,
      artwork: artwork,
      meta: {
        ...item,
        if (mediaMid.isNotEmpty) 'strMediaMid': mediaMid,
        if (mediaMid.isNotEmpty) 'media_mid': mediaMid,
        if (file != null) 'file': file,
      },
    );
  }

  void dispose() {
    _dio.close();
    closeReusedServiceClients();
  }
}
