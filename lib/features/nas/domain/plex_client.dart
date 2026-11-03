import 'package:dio/dio.dart';

import '../../player/domain/music_item.dart';
import 'nas_client.dart';
import 'nas_config.dart';
import 'nas_kind.dart';

class PlexPinSession {
  const PlexPinSession({
    required this.id,
    required this.code,
    required this.clientId,
  });

  final String id;
  final String code;
  final String clientId;
}

class PlexNasClient extends NasClient {
  PlexNasClient({Dio? dio, String? clientId})
      : _clientId = clientId ?? 'koyze-plex',
        super(dio: dio);

  /// PIN 登录拿到的 clientId 要沿用到后续请求，否则 plex.tv 那边
  /// 会认为是另一台设备，token 的授权关系对不上。
  String _clientId;

  String get clientId => _clientId;

  @override
  NasKind get kind => NasKind.plex;

  Map<String, String> _headers({String? token, String? clientId}) {
    return {
      'Accept': 'application/json',
      'X-Plex-Client-Identifier': clientId ?? _clientId,
      'X-Plex-Product': nasClientName,
      'X-Plex-Version': nasClientVersion,
      'X-Plex-Platform': 'Web',
      'X-Plex-Provides': 'player',
      'X-Plex-Device': 'Koyze',
      'X-Plex-Device-Name': 'Koyze',
      if (token != null && token.isNotEmpty) 'X-Plex-Token': token,
    };
  }

  Options _options({
    String? token,
    String? clientId,
    String contentType = 'application/json',
  }) {
    return Options(
      headers: {
        ..._headers(token: token, clientId: clientId),
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
      if (config.deviceId.isNotEmpty) _clientId = config.deviceId;
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
  Future<List<MusicItem>> getLibrarySongs(
    NasConfig config,
    NasSecrets secrets, {
    int limit = kNasLibraryLimit,
  }) async {
    final cap = limit < 1 ? kNasLibraryLimit : limit;
    final sections = _container(
      await _get('${config.baseUrl}/library/sections', token: secrets.token),
    );
    final musicKeys = asList(sections?['Directory'])
        .where((item) => item['type']?.toString() == 'artist')
        .map((item) => item['key']?.toString() ?? '')
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    final songs = <MusicItem>[];
    final seen = <String>{};
    for (final key in musicKeys) {
      if (songs.length >= cap) break;
      final data = _container(
        await _get(
          '${config.baseUrl}/library/sections/$key/all',
          token: secrets.token,
          query: {
            'type': 10,
            'sort': 'addedAt:desc',
            'X-Plex-Container-Start': 0,
            'X-Plex-Container-Size': cap,
          },
        ),
      );
      for (final item in asList(data?['Metadata'])) {
        final song = parseSong(config, secrets, item);
        if (song.id.isEmpty || !seen.add(song.id)) continue;
        songs.add(song);
        if (songs.length >= cap) break;
      }
    }
    return List<MusicItem>.unmodifiable(songs.take(cap));
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
    Object? bitRate;
    Object? container;
    Object? codec;
    if (media.isNotEmpty) {
      final first = media.first;
      bitRate = first['bitrate'] ?? first['bitRate'];
      container = first['container'];
      codec = first['audioCodec'];
      final parts = asList(first['Part']);
      if (parts.isNotEmpty) {
        partKey = parts.first['key']?.toString();
        bitRate ??= parts.first['bitrate'];
        container ??= parts.first['container'];
        final streams = asList(parts.first['Stream']);
        for (final stream in streams) {
          if (stream['streamType'] == 2) {
            bitRate ??= stream['bitrate'];
            codec ??= stream['codec'] ?? stream['audioCodec'];
          }
          if (stream['streamType'] == 4 ||
              stream['format']?.toString().toLowerCase() == 'lrc') {
            streamId ??= stream['id']?.toString();
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
        if (bitRate != null) 'bitRate': bitRate,
        if (container != null) 'container': container,
        if (codec != null) 'codec': codec,
      },
    );
  }

  /// 封面不再把 token 拼进 URL：图片加载器通过 [artworkHeaders] 拿凭证，
  /// 这样缓存下来的 MusicItem / 日志里不会留下长期有效的 Plex token。
  String coverUrl(NasConfig config, NasSecrets secrets, String thumb) {
    final _ = secrets;
    final thumbUrl = thumb.startsWith('http')
        ? thumb
        : '${config.baseUrl}$thumb';
    return '${config.baseUrl}/photo/:/transcode?width=300&height=300&minSize=1&upscale=1&url=${Uri.encodeQueryComponent(thumbUrl)}';
  }

  @override
  Map<String, String> artworkHeaders(NasConfig config, NasSecrets secrets) {
    final token = secrets.token ?? '';
    if (token.isEmpty) return const {};
    return {'X-Plex-Token': token};
  }

  @override
  Future<NasPlayUrlResult> streamResult(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music, {
    required String quality,
  }) async {
    return NasPlayUrlResult(
      url: streamUrl(config, secrets, music, quality: quality),
      headers: artworkHeaders(config, secrets),
      trustedNetwork: true,
    );
  }

  @override
  String streamUrl(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music, {
    required String quality,
  }) {
    final cap = nasBitrateCapKbps(quality);
    final partKey = music.meta?['partKey']?.toString();
    final hasPart = partKey != null && partKey.isNotEmpty;
    final partPath = hasPart
        ? (partKey.startsWith('/') ? partKey : '/$partKey')
        : null;
    if (cap == null && partPath != null) {
      return '${config.baseUrl}$partPath';
    }
    final id = music.songmid?.isNotEmpty == true ? music.songmid! : music.id;
    final session = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final query = <String, String>{
      'path': partPath ?? '/library/metadata/$id',
      'session': session,
      'X-Plex-Platform': 'Web',
    };
    if (cap != null) {
      // Plex 只有转码接口认码率上限；directPlay=0 才会真的压。
      query['directPlay'] = '0';
      query['directStream'] = '0';
      query['protocol'] = 'http';
      query['maxAudioBitrate'] = '$cap';
    } else {
      query['directPlay'] = '1';
    }
    final encoded = query.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return '${config.baseUrl}/music/:/transcode/universal/start?$encoded';
  }

  /// Plex 官方推荐的登录方式：生成登录码，用户去 plex.tv/link 输入，
  /// 客户端轮询拿 token。全程不需要把账号密码交给应用。
  Future<PlexPinSession> createPin({required String clientId}) async {
    try {
      final response = await dio.post<dynamic>(
        'https://plex.tv/api/v2/pins',
        queryParameters: const {'strong': 'true'},
        options: _options(clientId: clientId),
      );
      final data = asMap(response.data) ?? const {};
      final id = data['id']?.toString() ?? '';
      final code = data['code']?.toString() ?? '';
      if (id.isEmpty || code.isEmpty) {
        throw const NasApiException('Plex 未返回登录码');
      }
      return PlexPinSession(id: id, code: code, clientId: clientId);
    } on DioException catch (error) {
      throw NasApiException(
        describeDio(error),
        code: error.response?.statusCode,
      );
    }
  }

  /// 返回 null 表示用户还没在浏览器里授权。
  Future<String?> fetchPinToken(PlexPinSession session) async {
    try {
      final response = await dio.get<dynamic>(
        'https://plex.tv/api/v2/pins/${session.id}',
        options: _options(clientId: session.clientId),
      );
      final data = asMap(response.data) ?? const {};
      final token = data['authToken']?.toString();
      return token == null || token.isEmpty ? null : token;
    } on DioException catch (error) {
      throw NasApiException(
        describeDio(error),
        code: error.response?.statusCode,
      );
    }
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
