import 'package:dio/dio.dart';

import '../../../core/network/app_http_client.dart';
import '../../player/domain/music_item.dart';
import 'subsonic_auth.dart';
import 'subsonic_config.dart';

class SubsonicApiException implements Exception {
  const SubsonicApiException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

/// OpenSubsonic / Subsonic REST 客户端。独立实现，不依赖第三方播放器源码。
class SubsonicClient {
  SubsonicClient({
    Dio? dio,
    String Function()? saltGenerator,
  })  : _dio = dio ??
            AppHttpClient.create(
              options: BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
              ),
            ),
        _ownsDio = dio == null,
        _saltGenerator = saltGenerator;

  final Dio _dio;
  final bool _ownsDio;
  final String Function()? _saltGenerator;
  String? _stableSalt;

  void dispose() {
    if (_ownsDio) _dio.close(force: true);
  }

  Map<String, String> _auth(
    SubsonicConfig config,
    String password, {
    bool stable = false,
  }) {
    if (stable && !config.legacyAuth) {
      _stableSalt ??= (_saltGenerator ?? generateSubsonicSalt)();
    }
    return subsonicAuthParams(
      username: config.username,
      password: password,
      legacy: config.legacyAuth,
      salt: stable && !config.legacyAuth ? _stableSalt : null,
      saltGenerator: _saltGenerator,
    );
  }

  String _restUrl(
    SubsonicConfig config,
    String password,
    String endpoint, {
    Map<String, String>? extra,
    bool stable = false,
  }) {
    final params = _auth(config, password, stable: stable);
    if (extra != null) params.addAll(extra);
    final query = encodeSubsonicQuery(params);
    return '${config.baseUrl}/rest/$endpoint?$query';
  }

  Future<Map<String, dynamic>> _request(
    SubsonicConfig config,
    String password,
    String endpoint, [
    Map<String, String>? extra,
  ]) async {
    final url = _restUrl(config, password, endpoint, extra: extra);
    try {
      final response = await _dio.get<dynamic>(url);
      return _unwrap(response.data);
    } on DioException catch (error) {
      throw SubsonicApiException(_describeDio(error));
    }
  }

  Map<String, dynamic> _unwrap(dynamic data) {
    if (data is! Map) {
      throw const SubsonicApiException('服务器返回了无法解析的响应');
    }
    final root = Map<String, dynamic>.from(data);
    final envelope = root['subsonic-response'];
    if (envelope is! Map) {
      throw const SubsonicApiException('响应缺少 subsonic-response');
    }
    final payload = Map<String, dynamic>.from(envelope);
    final status = payload['status']?.toString();
    if (status != 'ok') {
      final error = payload['error'];
      if (error is Map) {
        throw SubsonicApiException(
          error['message']?.toString() ?? '服务器拒绝请求',
          code: error['code'] is int
              ? error['code'] as int
              : int.tryParse(error['code']?.toString() ?? ''),
        );
      }
      throw const SubsonicApiException('服务器拒绝请求');
    }
    return payload;
  }

  String _describeDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查服务器地址和网络';
      case DioExceptionType.connectionError:
        final message = error.message ?? '';
        if (message.contains('CERTIFICATE_VERIFY_FAILED')) {
          return '证书校验失败。自签名证书请改用受信证书，或在局域网使用 HTTP';
        }
        return '无法连接到服务器';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        if (code == 401 || code == 403) return '用户名或密码错误';
        if (code == 404) return '服务器路径不正确';
        if (code != null && code >= 500) return '服务器内部错误';
        return 'HTTP $code';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.unknown:
        return error.message ?? '未知网络错误';
      default:
        return error.message ?? '未知网络错误';
    }
  }

  Future<SubsonicPingResult> ping(
    SubsonicConfig config,
    String password,
  ) async {
    try {
      final payload = await _request(config, password, 'ping');
      final type = payload['type']?.toString();
      final version = payload['version']?.toString();
      final open = payload['openSubsonic'] == true ||
          payload['openSubsonic']?.toString() == 'true';
      return SubsonicPingResult(
        ok: true,
        serverType: type ?? (open ? 'OpenSubsonic' : 'Subsonic'),
        serverVersion: version,
        openSubsonic: open,
      );
    } on SubsonicApiException catch (error) {
      return SubsonicPingResult(ok: false, error: error.message);
    }
  }

  Future<List<SubsonicPlaylistInfo>> getPlaylists(
    SubsonicConfig config,
    String password,
  ) async {
    final payload = await _request(config, password, 'getPlaylists');
    final wrapper = payload['playlists'];
    final raw = wrapper is Map ? wrapper['playlist'] : null;
    return _asList(raw)
        .map(_parsePlaylistInfo)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<MusicItem>> getPlaylistSongs(
    SubsonicConfig config,
    String password,
    String playlistId,
  ) async {
    final payload = await _request(config, password, 'getPlaylist', {
      'id': playlistId,
    });
    final wrapper = payload['playlist'];
    final raw = wrapper is Map ? wrapper['entry'] : null;
    return _asList(raw)
        .map((item) => parseSong(config, password, item))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  static const librarySongLimit = 500;
  static const libraryAlbumLimit = 100;

  /// 浏览曲库歌曲（不依赖用户自建歌单）。
  ///
  /// 先拉最近专辑再展开曲目；没有专辑时退回 `getRandomSongs`。
  Future<List<MusicItem>> getLibrarySongs(
    SubsonicConfig config,
    String password, {
    int limit = librarySongLimit,
  }) async {
    final cap = limit < 1 ? librarySongLimit : limit;
    final albums = await _request(config, password, 'getAlbumList2', {
      'type': 'newest',
      'size': '$libraryAlbumLimit',
      'offset': '0',
    });
    final albumWrapper = albums['albumList2'] ?? albums['albumList'];
    final albumRaw = albumWrapper is Map ? albumWrapper['album'] : null;
    final albumIds = _asList(albumRaw)
        .map((item) => item['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final songs = <MusicItem>[];
    final seen = <String>{};
    for (final albumId in albumIds) {
      if (songs.length >= cap) break;
      final payload = await _request(config, password, 'getAlbum', {
        'id': albumId,
      });
      final wrapper = payload['album'];
      final raw = wrapper is Map ? wrapper['song'] : null;
      for (final item in _asList(raw)) {
        final song = parseSong(config, password, item);
        if (song.id.isEmpty || !seen.add(song.id)) continue;
        songs.add(song);
        if (songs.length >= cap) break;
      }
    }
    if (songs.isNotEmpty) return List<MusicItem>.unmodifiable(songs);

    try {
      final random = await _request(config, password, 'getRandomSongs', {
        'size': '$cap',
      });
      final wrapper = random['randomSongs'];
      final raw = wrapper is Map ? wrapper['song'] : null;
      return _asList(raw)
          .map((item) => parseSong(config, password, item))
          .where((item) => item.id.isNotEmpty)
          .take(cap)
          .toList(growable: false);
    } on SubsonicApiException {
      return const [];
    }
  }

  Future<List<MusicItem>> search(
    SubsonicConfig config,
    String password,
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final offset = ((page < 1 ? 1 : page) - 1) * limit;
    final payload = await _request(config, password, 'search3', {
      'query': query,
      'songCount': '$limit',
      'songOffset': '$offset',
      'artistCount': '0',
      'albumCount': '0',
    });
    final wrapper = payload['searchResult3'];
    final raw = wrapper is Map ? wrapper['song'] : null;
    return _asList(raw)
        .map((item) => parseSong(config, password, item))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<String?> getLyrics(
    SubsonicConfig config,
    String password,
    MusicItem music,
  ) async {
    try {
      final byId = await _request(config, password, 'getLyricsBySongId', {
        'id': music.id,
      });
      final parsed = _lyricsFromOpenSubsonic(byId);
      if (parsed != null && parsed.isNotEmpty) return parsed;
    } on SubsonicApiException {
      // OpenSubsonic 扩展，旧服没有这个接口。
    }
    try {
      final payload = await _request(config, password, 'getLyrics', {
        if (music.singer.trim().isNotEmpty) 'artist': music.singer,
        'title': music.name,
      });
      final lyrics = payload['lyrics'];
      if (lyrics is Map) {
        final value =
            lyrics['value']?.toString() ?? lyrics['content']?.toString();
        if (value != null && value.trim().isNotEmpty) return value;
      }
      if (lyrics is String && lyrics.trim().isNotEmpty) return lyrics;
    } on SubsonicApiException {
      // 部分服没有歌词，或按歌名匹配失败。播放不应因此中断。
    }
    return null;
  }

  String streamUrl(
    SubsonicConfig config,
    String password,
    String songId, {
    required String quality,
  }) {
    final extra = <String, String>{'id': songId};
    final bitrate = maxBitRateForQuality(quality);
    if (bitrate != null) extra['maxBitRate'] = '$bitrate';
    final format = streamFormatForQuality(quality);
    if (format != null) extra['format'] = format;
    return _restUrl(config, password, 'stream', extra: extra);
  }

  String coverArtUrl(
    SubsonicConfig config,
    String password,
    String coverArt, {
    int size = 300,
  }) {
    return _restUrl(
      config,
      password,
      'getCoverArt',
      extra: {
        'id': coverArt,
        if (size > 0) 'size': '$size',
      },
      stable: true,
    );
  }

  MusicItem parseSong(
    SubsonicConfig config,
    String password,
    Map<String, dynamic> raw,
  ) {
    final id = raw['id']?.toString() ?? '';
    final coverArt = raw['coverArt']?.toString();
    final durationSeconds = _asInt(raw['duration']) ?? 0;
    final artwork = coverArt == null || coverArt.isEmpty
        ? null
        : coverArtUrl(config, password, coverArt);
    return MusicItem(
      id: id,
      name: raw['title']?.toString() ?? '',
      singer: raw['artist']?.toString() ?? '',
      album: raw['album']?.toString() ?? '',
      duration: Duration(seconds: durationSeconds),
      source: 'subsonic',
      platform: 'subsonic',
      artwork: artwork,
      songmid: id,
      isPlayable: true,
      meta: {
        'subsonicId': id,
        if (coverArt != null) 'coverArt': coverArt,
        if (raw['suffix'] != null) 'suffix': raw['suffix'],
        if (raw['contentType'] != null) 'contentType': raw['contentType'],
        if (raw['bitRate'] != null) 'bitRate': raw['bitRate'],
      },
    );
  }

  static int? maxBitRateForQuality(String quality) {
    return switch (quality) {
      '128k' => 128,
      '192k' => 192,
      '320k' => 320,
      'flac' || 'flac24bit' || 'hires' => 0,
      _ => 320,
    };
  }

  static String? streamFormatForQuality(String quality) {
    return switch (quality) {
      'flac' || 'flac24bit' || 'hires' => 'raw',
      _ => null,
    };
  }

  SubsonicPlaylistInfo _parsePlaylistInfo(Map<String, dynamic> raw) {
    return SubsonicPlaylistInfo(
      id: raw['id']?.toString() ?? '',
      name: raw['name']?.toString() ?? '',
      songCount: _asInt(raw['songCount']) ?? 0,
      coverArt: raw['coverArt']?.toString(),
      owner: raw['owner']?.toString(),
      comment: raw['comment']?.toString(),
      created: DateTime.tryParse(raw['created']?.toString() ?? ''),
      changed: DateTime.tryParse(raw['changed']?.toString() ?? ''),
    );
  }

  String? _lyricsFromOpenSubsonic(Map<String, dynamic> payload) {
    final list = payload['lyricsList'];
    if (list is! Map) return null;
    final structured = list['structuredLyrics'];
    final items = _asList(structured);
    if (items.isEmpty) return null;
    final first = items.first;
    final lines = first['line'];
    if (lines is List) {
      final buffer = StringBuffer();
      for (final line in lines) {
        if (line is! Map) continue;
        final start = _asInt(line['start']);
        final value = line['value']?.toString() ?? '';
        if (value.isEmpty) continue;
        if (start != null) {
          final minutes = (start ~/ 60000).toString().padLeft(2, '0');
          final seconds = ((start % 60000) ~/ 1000).toString().padLeft(2, '0');
          final millis = (start % 1000).toString().padLeft(3, '0');
          buffer.writeln('[$minutes:$seconds.$millis]$value');
        } else {
          buffer.writeln(value);
        }
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) return text;
    }
    final value = first['value']?.toString();
    return value != null && value.trim().isNotEmpty ? value : null;
  }

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    if (raw is Map) return [Map<String, dynamic>.from(raw)];
    return const [];
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
