import 'dart:convert';

import 'package:dio/dio.dart';

import '../../player/domain/music_item.dart';
import 'nas_client.dart';
import 'nas_config.dart';
import 'nas_kind.dart';

class AudioStationNasClient extends NasClient {
  AudioStationNasClient({Dio? dio}) : super(dio: dio);

  @override
  NasKind get kind => NasKind.audiostation;

  dynamic _decode(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  Future<Map<String, dynamic>> _cgi(
    NasConfig config, {
    required String path,
    required Map<String, dynamic> query,
    String method = 'GET',
    String? sid,
  }) async {
    final params = <String, dynamic>{
      ...query,
      if (sid != null && sid.isNotEmpty) '_sid': sid,
    };
    try {
      final response = method == 'POST'
          ? await dio.post<dynamic>(
              '${config.baseUrl}$path',
              data: FormData.fromMap(
                params.map((key, value) => MapEntry(key, value.toString())),
              ),
            )
          : await dio.get<dynamic>(
              '${config.baseUrl}$path',
              queryParameters: params,
            );
      final decoded = _decode(response.data);
      final map = asMap(decoded);
      if (map == null) {
        throw const NasApiException('服务器返回了无法解析的响应');
      }
      if (map['success'] != true) {
        final error = asMap(map['error']);
        final code = asInt(error?['code']);
        throw NasApiException(_synoError(code), code: code);
      }
      return asMap(map['data']) ?? map;
    } on DioException catch (error) {
      throw NasApiException(describeDio(error), code: error.response?.statusCode);
    }
  }

  String _synoError(int? code) {
    return switch (code) {
      400 => '用户名或密码错误',
      401 => '账号被禁用',
      402 => '二次验证失败',
      403 => '权限不足',
      404 => '需要二次验证码',
      _ => code == null ? '群晖拒绝请求' : '群晖错误 $code',
    };
  }

  @override
  Future<NasPingResult> connect(NasConfig config, NasSecrets secrets) async {
    try {
      if (secrets.hasToken && !secrets.hasPassword) {
        await _cgi(
          config,
          path: '/webapi/AudioStation/playlist.cgi',
          query: {
            'api': 'SYNO.AudioStation.Playlist',
            'method': 'list',
            'version': 2,
            'limit': 1,
          },
          sid: secrets.token,
        );
        return NasPingResult(
          ok: true,
          serverType: 'Audio Station',
          token: secrets.token,
        );
      }
      if (!secrets.hasPassword) {
        return const NasPingResult(ok: false, error: '请输入密码');
      }
      if (config.username.trim().isEmpty) {
        return const NasPingResult(ok: false, error: '请输入用户名');
      }
      final data = await _cgi(
        config,
        path: '/webapi/auth.cgi',
        method: 'POST',
        query: {
          'api': 'SYNO.API.Auth',
          'method': 'login',
          'version': 6,
          'session': 'AudioStation',
          'account': config.username,
          'passwd': secrets.password,
          'format': 'sid',
          'enable_syno_token': 'yes',
        },
      );
      final sid = data['sid']?.toString();
      if (sid == null || sid.isEmpty) {
        return const NasPingResult(ok: false, error: '登录未返回会话');
      }
      return NasPingResult(
        ok: true,
        serverType: 'Audio Station',
        token: sid,
      );
    } on NasApiException catch (error) {
      return NasPingResult(ok: false, error: error.message);
    }
  }

  @override
  Future<List<NasPlaylistInfo>> getPlaylists(
    NasConfig config,
    NasSecrets secrets,
  ) async {
    final data = await _cgi(
      config,
      path: '/webapi/AudioStation/playlist.cgi',
      query: {
        'api': 'SYNO.AudioStation.Playlist',
        'method': 'list',
        'version': 2,
        'library': 'all',
        'offset': 0,
        'limit': 200,
      },
      sid: secrets.token,
    );
    return asList(data['playlists'])
        .map((item) {
          return NasPlaylistInfo(
            id: item['id']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            songCount: asInt(item['songs']) ??
                asInt(item['additional'] is Map
                    ? (item['additional'] as Map)['songs']
                    : null) ??
                asInt(item['total']) ??
                0,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<MusicItem>> getPlaylistSongs(
    NasConfig config,
    NasSecrets secrets,
    String playlistId,
  ) async {
    final data = await _cgi(
      config,
      path: '/webapi/AudioStation/playlist.cgi',
      query: {
        'api': 'SYNO.AudioStation.Playlist',
        'method': 'getinfo',
        'version': 2,
        'id': playlistId,
        'additional': 'songs,songs_song_tag,songs_song_audio',
        'limit': 1000,
      },
      sid: secrets.token,
    );
    final playlists = asList(data['playlists']);
    final songsRaw = playlists.isNotEmpty
        ? (asMap(playlists.first['additional'])?['songs'])
        : data['songs'];
    return asList(songsRaw)
        .map((item) => parseSong(config, secrets, item))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<MusicItem>> search(
    NasConfig config,
    NasSecrets secrets,
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final offset = ((page < 1 ? 1 : page) - 1) * limit;
    final data = await _cgi(
      config,
      path: '/webapi/AudioStation/search.cgi',
      query: {
        'api': 'SYNO.AudioStation.Search',
        'method': 'list',
        'version': 1,
        'keyword': query,
        'library': 'all',
        'offset': offset,
        'limit': limit,
        'additional': 'song_tag,song_audio',
      },
      sid: secrets.token,
    );
    return asList(data['songs'])
        .map((item) => parseSong(config, secrets, item))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  MusicItem parseSong(
    NasConfig config,
    NasSecrets secrets,
    Map<String, dynamic> raw,
  ) {
    final id = raw['id']?.toString() ?? '';
    final tag = asMap(raw['additional'] is Map
            ? (raw['additional'] as Map)['song_tag']
            : raw['tag']) ??
        asMap(raw['additional']) ??
        raw;
    final audio = asMap(raw['additional'] is Map
        ? (raw['additional'] as Map)['song_audio']
        : raw['audio']);
    final duration = asInt(audio?['duration']) ?? asInt(raw['duration']) ?? 0;
    return MusicItem(
      id: id,
      name: tag['title']?.toString() ?? raw['title']?.toString() ?? '',
      singer: tag['artist']?.toString() ?? raw['artist']?.toString() ?? '',
      album: tag['album']?.toString() ?? raw['album']?.toString() ?? '',
      duration: Duration(seconds: duration),
      source: kind.id,
      platform: kind.id,
      artwork: coverUrl(config, secrets, id),
      songmid: id,
      isPlayable: true,
      meta: {'nasId': id},
    );
  }

  String coverUrl(NasConfig config, NasSecrets secrets, String songId) {
    final sid = secrets.token ?? '';
    return '${config.baseUrl}/webapi/AudioStation/cover.cgi?api=SYNO.AudioStation.Cover&method=getsongcover&version=1&id=${Uri.encodeQueryComponent(songId)}&_sid=${Uri.encodeQueryComponent(sid)}';
  }

  @override
  String streamUrl(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music, {
    required String quality,
  }) {
    final id = music.songmid?.isNotEmpty == true ? music.songmid! : music.id;
    final sid = secrets.token ?? '';
    final bitrate = maxKbpsForQuality(quality);
    if (bitrate == null) {
      return '${config.baseUrl}/webapi/AudioStation/stream.cgi?api=SYNO.AudioStation.Stream&method=stream&version=2&id=${Uri.encodeQueryComponent(id)}&_sid=${Uri.encodeQueryComponent(sid)}';
    }
    return '${config.baseUrl}/webapi/AudioStation/stream.cgi/0.mp3?api=SYNO.AudioStation.Stream&method=transcode&version=2&id=${Uri.encodeQueryComponent(id)}&format=mp3&_sid=${Uri.encodeQueryComponent(sid)}';
  }

  @override
  Future<String?> getLyrics(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music,
  ) async {
    final id = music.songmid?.isNotEmpty == true ? music.songmid! : music.id;
    if (id.isEmpty) return null;
    try {
      final data = await _cgi(
        config,
        path: '/webapi/AudioStation/lyrics.cgi',
        query: {
          'api': 'SYNO.AudioStation.Lyrics',
          'method': 'getlyrics',
          'version': 2,
          'id': id,
        },
        sid: secrets.token,
      );
      final lyrics = data['lyrics']?.toString();
      if (lyrics != null && lyrics.trim().isNotEmpty) return lyrics;
    } on NasApiException {
      return null;
    }
    return null;
  }
}
