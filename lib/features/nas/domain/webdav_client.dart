import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../player/domain/music_item.dart';
import 'nas_client.dart';
import 'nas_config.dart';
import 'nas_kind.dart';

class WebDavNasClient extends NasClient {
  WebDavNasClient({Dio? dio}) : super(dio: dio);

  static const _propfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype />
    <d:getcontentlength />
    <d:getlastmodified />
    <d:getcontenttype />
    <d:displayname />
  </d:prop>
</d:propfind>''';

  static const _audioExtensions = {
    'mp3',
    'flac',
    'm4a',
    'aac',
    'wav',
    'ogg',
    'opus',
  };

  @override
  NasKind get kind => NasKind.webdav;

  Map<String, String> _authHeaders(NasConfig config, NasSecrets secrets) {
    if (config.authMethod == NasAuthMethod.bearer) {
      final token = secrets.token ?? '';
      return token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};
    }
    final password = secrets.password ?? '';
    if (config.username.isEmpty && password.isEmpty) return const {};
    final encoded = base64.encode(utf8.encode('${config.username}:$password'));
    return {'Authorization': 'Basic $encoded'};
  }

  Uri _rootUri(NasConfig config) {
    final base = Uri.parse(config.baseUrl);
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    final root = config.rootPath.trim();
    final rootPath = root.isEmpty || root == '/'
        ? basePath.isEmpty
              ? '/'
              : basePath
        : '$basePath/${root.replaceFirst(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '')}';
    final normalized = rootPath.isEmpty ? '/' : rootPath;
    return base.replace(
      path: normalized.endsWith('/') ? normalized : '$normalized/',
    );
  }

  Map<String, String> _requestHeaders(
    NasConfig config,
    NasSecrets secrets, {
    String? depth,
  }) {
    return {
      'Accept': 'application/xml, text/xml;q=0.9, */*;q=0.8',
      'Content-Type': 'application/xml; charset=utf-8',
      if (depth != null) 'Depth': depth,
      ..._authHeaders(config, secrets),
    };
  }

  Future<Response<String>> _propfind(
    NasConfig config,
    NasSecrets secrets,
    Uri uri, {
    required String depth,
  }) async {
    try {
      final response = await dio.request<String>(
        uri.toString(),
        data: _propfindBody,
        options: Options(
          method: 'PROPFIND',
          headers: _requestHeaders(config, secrets, depth: depth),
          responseType: ResponseType.plain,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw NasApiException(
          _statusMessage(response.statusCode),
          code: response.statusCode,
        );
      }
      return response;
    } on NasApiException {
      rethrow;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw NasApiException(
        status == 401 || status == 403 || status == 404 || status == 405
            ? _statusMessage(status)
            : describeDio(error),
        code: status,
      );
    }
  }

  String _statusMessage(int? status) {
    if (status == 401 || status == 403) return 'WebDAV 用户名、密码或 token 错误';
    if (status == 404) return 'WebDAV 地址或根目录不存在';
    if (status == 405) return '服务器不支持 PROPFIND，请确认已启用 WebDAV';
    if (status != null && status >= 500) return 'WebDAV 服务器内部错误';
    return status == null ? 'WebDAV 请求失败' : 'WebDAV HTTP $status';
  }

  @override
  Future<NasPingResult> connect(NasConfig config, NasSecrets secrets) async {
    if (config.authMethod == NasAuthMethod.bearer && !secrets.hasToken) {
      return const NasPingResult(ok: false, error: '请输入 Bearer token');
    }
    if (config.authMethod == NasAuthMethod.basic && !secrets.hasPassword) {
      return const NasPingResult(ok: false, error: '请输入 WebDAV 密码');
    }
    try {
      final response = await _propfind(
        config,
        secrets,
        _rootUri(config),
        depth: '0',
      );
      final server = response.headers.value('server');
      return NasPingResult(
        ok: true,
        serverType: 'WebDAV',
        serverVersion: server,
      );
    } on NasApiException catch (error) {
      return NasPingResult(ok: false, error: error.message);
    }
  }

  @override
  Future<List<NasPlaylistInfo>> getPlaylists(
    NasConfig config,
    NasSecrets secrets,
  ) async => const [];

  @override
  Future<List<MusicItem>> getPlaylistSongs(
    NasConfig config,
    NasSecrets secrets,
    String playlistId,
  ) async => const [];

  @override
  Future<List<MusicItem>> getLibrarySongs(
    NasConfig config,
    NasSecrets secrets, {
    int limit = 500,
  }) async {
    final cap = limit < 1 ? 500 : limit;
    final songs = <MusicItem>[];
    final pending = <Uri>[_rootUri(config)];
    final visitedDirectories = <String>{};
    final seenFiles = <String>{};
    while (pending.isNotEmpty && songs.length < cap) {
      final directory = pending.removeAt(0);
      final directoryKey = _withoutTrailingSlash(directory.path);
      if (!visitedDirectories.add(directoryKey)) continue;
      final response = await _propfind(config, secrets, directory, depth: '1');
      for (final item in _parseResponses(
        config,
        response.data ?? '',
        directory,
      )) {
        if (item.isDirectory) {
          if (_withoutTrailingSlash(item.uri.path) != directoryKey &&
              _isInRoot(config, item.uri)) {
            pending.add(item.uri.removeFragment());
          }
          continue;
        }
        final song = _songFromEntry(config, item);
        if (song == null) continue;
        if (!seenFiles.add(song.songmid ?? song.id)) continue;
        songs.add(song);
        if (songs.length >= cap) break;
      }
    }
    return List<MusicItem>.unmodifiable(songs);
  }

  @override
  Future<List<MusicItem>> search(
    NasConfig config,
    NasSecrets secrets,
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final all = await getLibrarySongs(config, secrets, limit: 5000);
    final normalized = query.trim().toLowerCase();
    final matches = normalized.isEmpty
        ? all
        : all
              .where((song) {
                return song.name.toLowerCase().contains(normalized) ||
                    song.singer.toLowerCase().contains(normalized) ||
                    song.album.toLowerCase().contains(normalized);
              })
              .toList(growable: false);
    final start = ((page < 1 ? 1 : page) - 1) * limit;
    if (start >= matches.length) return const [];
    return matches.skip(start).take(limit).toList(growable: false);
  }

  @override
  String streamUrl(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music, {
    required String quality,
  }) {
    final _ = quality;
    final value = music.meta?['webdavUrl']?.toString();
    if (value != null && value.isNotEmpty) return value;
    return music.songmid?.isNotEmpty == true ? music.songmid! : music.id;
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
      headers: _authHeaders(config, secrets),
      trustedNetwork: true,
    );
  }

  @override
  Future<String?> getLyrics(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music,
  ) async => null;

  List<_WebDavEntry> _parseResponses(
    NasConfig config,
    String xml,
    Uri baseUri,
  ) {
    if (xml.trim().isEmpty) return const [];
    try {
      final document = XmlDocument.parse(xml);
      final entries = <_WebDavEntry>[];
      for (final response in document.descendants.whereType<XmlElement>().where(
        (element) => element.localName == 'response',
      )) {
        final href = _firstChildText(response, 'href');
        if (href == null || href.trim().isEmpty) continue;
        final uri = _resolveHref(baseUri, href.trim());
        if (uri == null || !_isInRoot(config, uri)) continue;
        final prop = _firstProp(response);
        final isDirectory =
            prop != null &&
            prop.descendants.whereType<XmlElement>().any(
              (element) => element.localName == 'collection',
            );
        final name = _firstChildText(prop, 'displayname');
        final length = int.tryParse(
          _firstChildText(prop, 'getcontentlength') ?? '',
        );
        final modified = _parseHttpDate(
          _firstChildText(prop, 'getlastmodified'),
        );
        final contentType = _firstChildText(prop, 'getcontenttype');
        entries.add(
          _WebDavEntry(
            uri: uri,
            isDirectory: isDirectory,
            displayName: name,
            sizeBytes: length,
            modifiedAt: modified,
            contentType: contentType,
          ),
        );
      }
      return entries;
    } on XmlException catch (error) {
      throw NasApiException('WebDAV XML 响应无法解析: $error');
    }
  }

  XmlElement? _firstProp(XmlElement response) {
    for (final element in response.descendants.whereType<XmlElement>()) {
      if (element.localName == 'prop') return element;
    }
    return null;
  }

  String? _firstChildText(XmlNode? parent, String localName) {
    if (parent == null) return null;
    for (final element in parent.descendants.whereType<XmlElement>()) {
      if (element.localName == localName) return element.innerText.trim();
    }
    return null;
  }

  Uri? _resolveHref(Uri base, String href) {
    try {
      final parsed = Uri.parse(href);
      final Uri resolved;
      if (parsed.hasScheme) {
        resolved = parsed;
      } else if (href.startsWith('/')) {
        // `Uri.replace(path:)` would re-escape percent sequences and turn
        // `/a%20b` into `/a%2520b`. Concatenate the raw reference instead.
        resolved = Uri.parse('${base.scheme}://${base.authority}$href');
      } else {
        resolved = base.resolveUri(parsed);
      }
      return resolved.removeFragment();
    } catch (_) {
      return null;
    }
  }

  bool _isInRoot(NasConfig config, Uri uri) {
    final root = _rootUri(config);
    if (uri.scheme.toLowerCase() != root.scheme.toLowerCase() ||
        uri.host.toLowerCase() != root.host.toLowerCase() ||
        uri.port != root.port) {
      return false;
    }
    final rootPath = _withoutTrailingSlash(root.path);
    final path = _withoutTrailingSlash(uri.path);
    return path == rootPath || path.startsWith('$rootPath/');
  }

  MusicItem? _songFromEntry(NasConfig config, _WebDavEntry entry) {
    final extension = _extension(entry.uri.path);
    if (extension == null || !_audioExtensions.contains(extension)) return null;
    final name = entry.displayName?.trim().isNotEmpty == true
        ? entry.displayName!.trim()
        : _basename(entry.uri.path);
    final title = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final url = entry.uri.toString();
    final folders = _foldersFromRoot(config, entry.uri);
    return MusicItem(
      id: url,
      name: title.isEmpty ? name : title,
      singer: folders.isNotEmpty ? folders.first : '',
      album: folders.length > 1
          ? folders[1]
          : (folders.isNotEmpty ? folders.first : ''),
      source: kind.id,
      platform: kind.id,
      songmid: url,
      isPlayable: true,
      meta: {
        'webdavUrl': url,
        if (folders.isNotEmpty) 'folder': folders.join('/'),
        if (entry.sizeBytes != null) 'fileSize': entry.sizeBytes,
        if (entry.modifiedAt != null)
          'lastModified': entry.modifiedAt!.millisecondsSinceEpoch,
        if (entry.contentType != null && entry.contentType!.isNotEmpty)
          'contentType': entry.contentType,
        'suffix': extension,
        'container': extension.substring(1),
      },
    );
  }

  List<String> _foldersFromRoot(NasConfig config, Uri uri) {
    final root = _withoutTrailingSlash(_rootUri(config).path);
    final path = _withoutTrailingSlash(uri.path);
    if (!path.startsWith('$root/')) return const [];
    final relative = path.substring(root.length + 1);
    final segments = relative
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (segments.isEmpty) return const [];
    segments.removeLast();
    return segments
        .map((part) {
          try {
            return Uri.decodeComponent(part);
          } catch (_) {
            return part;
          }
        })
        .toList(growable: false);
  }

  String? _extension(String path) {
    final name = _basename(path).toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1);
  }

  String _basename(String path) {
    final clean = path.replaceFirst(RegExp(r'/+$'), '');
    final slash = clean.lastIndexOf('/');
    return slash < 0 ? clean : Uri.decodeComponent(clean.substring(slash + 1));
  }

  String _withoutTrailingSlash(String value) {
    final result = value.replaceFirst(RegExp(r'/+$'), '');
    return result.isEmpty ? '/' : result;
  }

  DateTime? _parseHttpDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return HttpDate.parse(value);
    } catch (_) {
      return DateTime.tryParse(value);
    }
  }
}

class _WebDavEntry {
  const _WebDavEntry({
    required this.uri,
    required this.isDirectory,
    this.displayName,
    this.sizeBytes,
    this.modifiedAt,
    this.contentType,
  });

  final Uri uri;
  final bool isDirectory;
  final String? displayName;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? contentType;
}
