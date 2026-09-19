import 'package:dio/dio.dart';

import '../../player/domain/music_item.dart';
import 'nas_client.dart';
import 'nas_config.dart';
import 'nas_kind.dart';

class PlexNasClient extends NasClient {
  PlexNasClient({Dio? dio, String? clientId})
      : _clientId = clientId ?? 'koyze-plex',
        super(dio: dio);

  final String _clientId;

  @override
  NasKind get kind => NasKind.plex;

  Map<String, String> _headers({String? token}) {
    return {
      'Accept': 'application/json',
      'X-Plex-Client-Identifier': _clientId,
      'X-Plex-Product': nasClientName,
      'X-Plex-Version': nasClientVersion,
      'X-Plex-Platform': 'Web',
      'X-Plex-Provides': 'player',
      'X-Plex-Device': 'Koyze',
      'X-Plex-Device-Name': 'Koyze',
      if (token != null && token.isNotEmpty) 'X-Plex-Token': token,
    };
  }

  Options _options({String? token, String contentType = 'application/json'}) {
    return Options(
      headers: {
        ..._headers(token: token),
        'Content-Type': contentType,
      },
    );
  }

  Future<dynamic> _get(
    String url, {
    String? token,
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await dio.get<dynamic>(
        url,
        queryParameters: query,
        options: _options(token: token),
      );
      return response.data;
    } on DioException catch (error) {
      throw NasApiException(describeDio(error), code: error.response?.statusCode);
    }
  }

  Future<String> _resolveToken(NasConfig config, NasSecrets secrets) async {
    if (secrets.hasToken) return secrets.token!;
    if (!secrets.hasPassword) {
      throw const NasApiException('请输入密码或 X-Plex-Token');
    }
    if (config.username.trim().isEmpty) {
      throw const NasApiException('请输入用户名，或把用户名留空并粘贴 X-Plex-Token');
    }
    try {
      final response = await dio.post<dynamic>(
        'https://plex.tv/api/v2/users/signin',
        data: {
          'login': config.username,
          'password': secrets.password,
          'rememberMe': true,
        },
        options: _options(),
      );
      final data = asMap(response.data) ??
          asMap(asMap(response.data)?['user']) ??
          const <String, dynamic>{};
      final token = data['authToken']?.toString() ??
          data['authentication_token']?.toString() ??
          asMap(data['user'])?['authToken']?.toString();
      if (token == null || token.isEmpty) {
        throw const NasApiException('Plex 登录未返回令牌');
      }
      return token;
    } on DioException catch (error) {
      throw NasApiException(describeDio(error), code: error.response?.statusCode);
    }
  }

  @override
  Future<NasPingResult> connect(NasConfig config, NasSecrets secrets) async {
    try {
      final token = await _resolveToken(config, secrets);
      final data = asMap(await _get(config.baseUrl, token: token));
      final container = asMap(data?['MediaContainer']) ?? data;
      return NasPingResult(
        ok: true,
        serverType: 'Plex',
        serverVersion: container?['version']?.toString(),
        token: token,
      );
    } on NasApiException catch (error) {
      return NasPingResult(ok: false, error: error.message);
    }
  }

  Map<String, dynamic>? _container(dynamic data) {
    return asMap(asMap(data)?['MediaContainer']) ?? asMap(data);
  }

  @override
  Future<List<NasPlaylistInfo>> getPlaylists(
    NasConfig config,
    NasSecrets secrets,
  ) async {
    final data = _container(
      await _get(
        '${config.baseUrl}/playlists',
        token: secrets.token,
        query: {'playlistType': 'audio'},
      ),
    );
    return asList(data?['Metadata'] ?? data?['Playlist'])
        .map((item) {
          final id = item['ratingKey']?.toString() ?? item['key']?.toString() ?? '';
          return NasPlaylistInfo(
            id: id,
            name: item['title']?.toString() ?? '',
            songCount: asInt(item['leafCount']) ?? 0,
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
    final data = _container(
      await _get(
        '${config.baseUrl}/playlists/$playlistId/items',
        token: secrets.token,
        query: {'type': 'track'},
      ),
    );
    return asList(data?['Metadata'])
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
    final start = ((page < 1 ? 1 : page) - 1) * limit;
    final sections = _container(
      await _get('${config.baseUrl}/library/sections', token: secrets.token),
    );
    final musicKeys = asList(sections?['Directory'])
        .where((item) => item['type']?.toString() == 'artist')
        .map((item) => item['key']?.toString() ?? '')
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    final songs = <MusicItem>[];
    for (final key in musicKeys) {
      final data = _container(
        await _get(
          '${config.baseUrl}/library/sections/$key/all',
          token: secrets.token,
          query: {
            'type': 10,
            'title': query,
            'X-Plex-Container-Start': start,
            'X-Plex-Container-Size': limit,
          },
        ),
      );
      songs.addAll(
        asList(data?['Metadata']).map(
          (item) => parseSong(config, secrets, item),
        ),
      );
      if (songs.length >= limit) break;
    }
    if (songs.isEmpty) {
      final hub = _container(
        await _get(
          '${config.baseUrl}/hubs/search',
          token: secrets.token,
          query: {
            'query': query,
            'limit': limit,
          },
        ),
      );
      for (final directory in asList(hub?['Hub'] ?? hub?['Directory'])) {
        if (directory['type']?.toString() != 'track') continue;
        songs.addAll(
          asList(directory['Metadata']).map(
            (item) => parseSong(config, secrets, item),
          ),
        );
      }
    }
    return songs.take(limit).toList(growable: false);
  }

  MusicItem parseSong(
    NasConfig config,
    NasSecrets secrets,
    Map<String, dynamic> raw,
  ) {
    final id = raw['ratingKey']?.toString() ?? '';
    final durationMs = asInt(raw['duration']) ?? 0;
    final media = asList(raw['Media']);
    String? partKey;
    String? streamId;
    if (media.isNotEmpty) {
      final parts = asList(media.first['Part']);
      if (parts.isNotEmpty) {
        partKey = parts.first['key']?.toString();
        final streams = asList(parts.first['Stream']);
        for (final stream in streams) {
          if (stream['streamType'] == 4 ||
              stream['format']?.toString().toLowerCase() == 'lrc') {
            streamId = stream['id']?.toString();
            break;
          }
        }
      }
    }
    final thumb = raw['thumb']?.toString();
    return MusicItem(
      id: id,
      name: raw['title']?.toString() ?? '',
      singer: raw['grandparentTitle']?.toString() ??
          raw['originalTitle']?.toString() ??
          '',
      album: raw['parentTitle']?.toString() ?? '',
      duration: Duration(milliseconds: durationMs),
      source: kind.id,
      platform: kind.id,
      artwork: thumb == null || thumb.isEmpty
          ? null
          : coverUrl(config, secrets, thumb),
      songmid: id,
      isPlayable: true,
      meta: {
        'nasId': id,
        if (partKey != null) 'partKey': partKey,
        if (streamId != null) 'lyricStreamId': streamId,
      },
    );
  }

  String coverUrl(NasConfig config, NasSecrets secrets, String thumb) {
    final token = secrets.token ?? '';
    final thumbUrl = thumb.startsWith('http')
        ? thumb
        : '${config.baseUrl}$thumb';
    return '${config.baseUrl}/photo/:/transcode?width=300&height=300&minSize=1&upscale=1&url=${Uri.encodeQueryComponent('$thumbUrl?X-Plex-Token=$token')}&X-Plex-Token=$token';
  }

  @override
  String streamUrl(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music, {
    required String quality,
  }) {
    final token = secrets.token ?? '';
    final bitrate = maxKbpsForQuality(quality);
    final partKey = music.meta?['partKey']?.toString();
    if (bitrate == null && partKey != null && partKey.isNotEmpty) {
      final path = partKey.startsWith('/') ? partKey : '/$partKey';
      return '${config.baseUrl}$path?X-Plex-Token=$token&X-Plex-Platform=Web';
    }
    final id = music.songmid?.isNotEmpty == true ? music.songmid! : music.id;
    final session = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final query = <String, String>{
      'path': '/library/metadata/$id',
      'directPlay': bitrate == null ? '1' : '0',
      'session': session,
      'X-Plex-Token': token,
      'X-Plex-Platform': 'Web',
      if (bitrate != null) 'musicBitrate': '${bitrate * 1000}',
    };
    final encoded = query.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return '${config.baseUrl}/music/:/transcode/universal/start?$encoded';
  }

  @override
  Future<String?> getLyrics(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music,
  ) async {
    final streamId = music.meta?['lyricStreamId']?.toString();
    if (streamId == null || streamId.isEmpty) return null;
    try {
      final data = asMap(
        await _get(
          '${config.baseUrl}/library/streams/$streamId',
          token: secrets.token,
          query: {'format': 'json'},
        ),
      );
      final container = asMap(data?['MediaContainer']) ?? data;
      final lyrics = asList(container?['Lyrics']);
      if (lyrics.isEmpty) return null;
      final buffer = StringBuffer();
      for (final line in asList(lyrics.first['Line'])) {
        final spans = asList(line['Span']);
        final start = asInt(line['startOffset']);
        final text = spans.isNotEmpty
            ? spans.map((span) => span['text']?.toString() ?? '').join()
            : line['text']?.toString() ?? '';
        if (text.isEmpty) continue;
        if (start != null) {
          final minutes = (start ~/ 60000).toString().padLeft(2, '0');
          final seconds = ((start % 60000) ~/ 1000).toString().padLeft(2, '0');
          final millis = (start % 1000).toString().padLeft(3, '0');
          buffer.writeln('[$minutes:$seconds.$millis]$text');
        } else {
          buffer.writeln(text);
        }
      }
      final result = buffer.toString().trim();
      return result.isEmpty ? null : result;
    } on NasApiException {
      return null;
    }
  }
}
