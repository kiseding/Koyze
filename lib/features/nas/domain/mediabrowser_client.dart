import 'package:dio/dio.dart';

import '../../player/domain/music_item.dart';
import 'nas_client.dart';
import 'nas_config.dart';
import 'nas_kind.dart';

/// Shared Emby / Jellyfin MediaBrowser REST client.
class MediaBrowserNasClient extends NasClient {
  MediaBrowserNasClient({
    required this.kind,
    Dio? dio,
    String? deviceId,
  })  : _deviceId = deviceId ?? 'koyze-${kind.id}',
        super(dio: dio);

  @override
  final NasKind kind;
  final String _deviceId;

  bool get _isJellyfin => kind == NasKind.jellyfin;

  String _authHeader({String? token}) {
    final parts = <String>[
      'MediaBrowser Client="$nasClientName"',
      'Device="Koyze"',
      'DeviceId="$_deviceId"',
      'Version="$nasClientVersion"',
      if (token != null && token.isNotEmpty) 'Token="$token"',
    ];
    return parts.join(', ');
  }

  Options _options({String? token, String? method}) {
    return Options(
      method: method,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': _authHeader(token: token),
        if (token != null && token.isNotEmpty) 'X-Emby-Token': token,
      },
    );
  }

  Future<dynamic> _get(
    NasConfig config,
    NasSecrets secrets,
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await dio.get<dynamic>(
        '${config.baseUrl}$path',
        queryParameters: query,
        options: _options(token: secrets.token),
      );
      return response.data;
    } on DioException catch (error) {
      throw NasApiException(describeDio(error), code: error.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> _post(
    NasConfig config,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    try {
      final response = await dio.post<dynamic>(
        '${config.baseUrl}$path',
        data: body,
        options: _options(token: token),
      );
      final map = asMap(response.data);
      if (map == null) {
        throw const NasApiException('服务器返回了无法解析的响应');
      }
      return map;
    } on DioException catch (error) {
      throw NasApiException(describeDio(error), code: error.response?.statusCode);
    }
  }

  @override
  Future<NasPingResult> connect(NasConfig config, NasSecrets secrets) async {
    try {
      String? token = secrets.token;
      String? userId = config.userId;
      if (secrets.hasPassword) {
        final payload = await _post(
          config,
          '/Users/AuthenticateByName',
          body: {
            'Username': config.username,
            'Pw': secrets.password,
          },
        );
        token = payload['AccessToken']?.toString();
        userId = asMap(payload['User'])?['Id']?.toString() ?? userId;
      }
      if (token == null || token.isEmpty) {
        return const NasPingResult(ok: false, error: '请输入密码');
      }
      String? version;
      try {
        final info = asMap(
          await _get(
            config,
            NasSecrets(token: token, password: secrets.password),
            '/System/Info/Public',
          ),
        );
        version = info?['Version']?.toString();
      } catch (_) {}
      return NasPingResult(
        ok: true,
        serverType: kind.title,
        serverVersion: version,
        userId: userId,
        token: token,
      );
    } on NasApiException catch (error) {
      return NasPingResult(ok: false, error: error.message);
    }
  }

  String _userId(NasConfig config) {
    if (config.userId.isNotEmpty) return config.userId;
    throw const NasApiException('缺少用户 ID，请重新连接');
  }

  @override
  Future<List<NasPlaylistInfo>> getPlaylists(
    NasConfig config,
    NasSecrets secrets,
  ) async {
    final data = asMap(
      await _get(
        config,
        secrets,
        '/Users/${_userId(config)}/Items',
        query: {
          'IncludeItemTypes': 'Playlist',
          'Recursive': 'true',
          'SortBy': 'SortName',
          'Fields': 'ChildCount,CumulativeRunTimeTicks',
          'StartIndex': 0,
          'Limit': 200,
        },
      ),
    );
    return asList(data?['Items'])
        .where((item) {
          final media = item['MediaType']?.toString();
          return media == null || media.isEmpty || media == 'Audio';
        })
        .map(_parsePlaylist)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  NasPlaylistInfo _parsePlaylist(Map<String, dynamic> raw) {
    final id = raw['Id']?.toString() ?? '';
    return NasPlaylistInfo(
      id: id,
      name: raw['Name']?.toString() ?? '',
      songCount: asInt(raw['ChildCount']) ?? 0,
      coverArt: id.isEmpty ? null : id,
    );
  }

  @override
  Future<List<MusicItem>> getPlaylistSongs(
    NasConfig config,
    NasSecrets secrets,
    String playlistId,
  ) async {
    if (_isJellyfin) {
      final data = asMap(
        await _get(
          config,
          secrets,
          '/Playlists/$playlistId/Items',
          query: {
            'userId': _userId(config),
            'Fields': 'MediaSources,RunTimeTicks,AlbumArtist,Album',
          },
        ),
      );
      return asList(data?['Items'])
          .map((item) => parseSong(config, secrets, item))
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false);
    }
    final data = asMap(
      await _get(
        config,
        secrets,
        '/Users/${_userId(config)}/Items',
        query: {
          'ParentId': playlistId,
          'IncludeItemTypes': 'Audio',
          'Recursive': 'true',
          'SortBy': 'ListItemOrder',
          'Fields': 'MediaSources,RunTimeTicks,AlbumArtist,Album',
        },
      ),
    );
    return asList(data?['Items'])
        .map((item) => parseSong(config, secrets, item))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<MusicItem>> getLibrarySongs(
    NasConfig config,
    NasSecrets secrets, {
    int limit = 500,
  }) async {
    final cap = limit < 1 ? 500 : limit;
    final data = asMap(
      await _get(
        config,
        secrets,
        '/Users/${_userId(config)}/Items',
        query: {
          'IncludeItemTypes': 'Audio',
          'Recursive': 'true',
          'SortBy': 'DateCreated,SortName',
          'SortOrder': 'Descending',
          'Fields': 'MediaSources,RunTimeTicks,AlbumArtist,Album',
          'StartIndex': 0,
          'Limit': cap,
        },
      ),
    );
    return asList(data?['Items'])
        .map((item) => parseSong(config, secrets, item))
        .where((item) => item.id.isNotEmpty)
        .take(cap)
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
    final data = asMap(
      await _get(
        config,
        secrets,
        '/Users/${_userId(config)}/Items',
        query: {
          'SearchTerm': query,
          'IncludeItemTypes': 'Audio',
          'Recursive': 'true',
          'Fields': 'MediaSources,RunTimeTicks,AlbumArtist,Album',
          'StartIndex': start,
          'Limit': limit,
        },
      ),
    );
    return asList(data?['Items'])
        .map((item) => parseSong(config, secrets, item))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  MusicItem parseSong(
    NasConfig config,
    NasSecrets secrets,
    Map<String, dynamic> raw,
  ) {
    final id = raw['Id']?.toString() ?? '';
    final ticks = asInt(raw['RunTimeTicks']) ?? 0;
    final seconds = ticks > 0 ? (ticks / 10000000).round() : 0;
    final albumArtist = raw['AlbumArtist']?.toString();
    final artists = asList(raw['Artists']);
    final singer = albumArtist?.isNotEmpty == true
        ? albumArtist!
        : artists.isNotEmpty
            ? artists.map((item) => item['Name'] ?? item.toString()).join(', ')
            : (raw['Artists'] is List
                ? (raw['Artists'] as List).map((e) => e.toString()).join(', ')
                : '');
    final mediaSources = asList(raw['MediaSources']);
    String? mediaSourceId;
    int? lyricIndex;
    Object? bitRate;
    Object? container;
    Object? codec;
    if (mediaSources.isNotEmpty) {
      final source = mediaSources.first;
      mediaSourceId = source['Id']?.toString();
      container = source['Container'];
      bitRate = source['Bitrate'] ?? source['BitRate'];
      final streams = asList(source['MediaStreams']);
      for (final stream in streams) {
        final type = stream['Type']?.toString();
        final streamCodec = stream['Codec']?.toString().toLowerCase();
        if (type == 'Audio') {
          codec ??= stream['Codec'];
          bitRate ??= stream['BitRate'] ?? stream['Bitrate'];
        }
        if (type == 'Subtitle' &&
            (streamCodec == 'lrc' ||
                streamCodec == 'text' ||
                streamCodec == 'subrip')) {
          lyricIndex = asInt(stream['Index']);
        }
      }
    }
    return MusicItem(
      id: id,
      name: raw['Name']?.toString() ?? '',
      singer: singer,
      album: raw['Album']?.toString() ?? '',
      duration: Duration(seconds: seconds),
      source: kind.id,
      platform: kind.id,
      artwork: coverUrl(config, secrets, id),
      songmid: id,
      isPlayable: true,
      meta: {
        'nasId': id,
        if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
        if (lyricIndex != null) 'lyricIndex': lyricIndex,
        if (bitRate != null) 'bitRate': bitRate,
        if (container != null) 'container': container,
        if (codec != null) 'codec': codec,
      },
    );
  }

  String coverUrl(NasConfig config, NasSecrets secrets, String itemId) {
    final token = secrets.token ?? '';
    return '${config.baseUrl}/Items/$itemId/Images/Primary?maxHeight=300&maxWidth=300&api_key=$token';
  }

  @override
  String streamUrl(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music, {
    required String quality,
  }) {
    final _ = quality;
    final id = music.songmid?.isNotEmpty == true ? music.songmid! : music.id;
    final token = secrets.token ?? '';
    final query = <String, String>{
      'api_key': token,
      'static': 'true',
    };
    final encoded = query.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return '${config.baseUrl}/Audio/$id/stream?$encoded';
  }

  @override
  Future<String?> getLyrics(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music,
  ) async {
    final id = music.songmid?.isNotEmpty == true ? music.songmid! : music.id;
    if (id.isEmpty) return null;
    if (_isJellyfin) {
      try {
        final data = asMap(await _get(config, secrets, '/Audio/$id/Lyrics'));
        final parsed = _lyricsFromJellyfin(data);
        if (parsed != null && parsed.isNotEmpty) return parsed;
      } on NasApiException {
        // Older servers may not expose /Audio/{id}/Lyrics.
      }
    }
    final mediaSourceId = music.meta?['mediaSourceId']?.toString();
    final lyricIndex = asInt(music.meta?['lyricIndex']);
    if (mediaSourceId == null || lyricIndex == null) return null;
    try {
      final data = asMap(
        await _get(
          config,
          secrets,
          '/Items/$id/$mediaSourceId/Subtitles/$lyricIndex/Stream.js',
        ),
      );
      return _lyricsFromEmbyTrackEvents(data);
    } on NasApiException {
      return null;
    }
  }

  String? _lyricsFromJellyfin(Map<String, dynamic>? data) {
    if (data == null) return null;
    final lines = asList(data['Lyrics']);
    if (lines.isEmpty) {
      final value = data['Lyrics']?.toString();
      return value != null && value.trim().isNotEmpty ? value : null;
    }
    final buffer = StringBuffer();
    for (final line in lines) {
      final text = line['Text']?.toString() ?? '';
      if (text.isEmpty) continue;
      final start = asInt(line['Start']);
      if (start != null && start > 0) {
        buffer.writeln('${_formatTicks(start)}$text');
      } else {
        buffer.writeln(text);
      }
    }
    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  String? _lyricsFromEmbyTrackEvents(Map<String, dynamic>? data) {
    if (data == null) return null;
    final events = asList(data['TrackEvents']);
    if (events.isEmpty) return null;
    final buffer = StringBuffer();
    for (final event in events) {
      final text = event['Text']?.toString() ?? '';
      if (text.isEmpty) continue;
      final start = asInt(event['StartPositionTicks']);
      if (start != null && start > 0) {
        buffer.writeln('${_formatTicks(start)}$text');
      } else {
        buffer.writeln(text);
      }
    }
    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  String _formatTicks(int ticks) {
    final millis = ticks ~/ 10000;
    final minutes = (millis ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((millis % 60000) ~/ 1000).toString().padLeft(2, '0');
    final rest = (millis % 1000).toString().padLeft(3, '0');
    return '[$minutes:$seconds.$rest]';
  }
}

class EmbyNasClient extends MediaBrowserNasClient {
  EmbyNasClient({Dio? dio, String? deviceId})
      : super(kind: NasKind.emby, dio: dio, deviceId: deviceId);
}

class JellyfinNasClient extends MediaBrowserNasClient {
  JellyfinNasClient({Dio? dio, String? deviceId})
      : super(kind: NasKind.jellyfin, dio: dio, deviceId: deviceId);
}
