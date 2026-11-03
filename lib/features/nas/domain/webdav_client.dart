import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../lyric/domain/local_lyric_file.dart' show decodeLyricBytes;
import '../../player/domain/music_item.dart';
import 'nas_client.dart';
import 'nas_config.dart';
import 'nas_kind.dart';

/// 目录选择器返回的一项。`path` 是相对服务地址的路径，`/` 代表服务根。
class WebDavDirectory {
  const WebDavDirectory({required this.name, required this.path});

  final String name;
  final String path;
}

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

  /// 与本地扫描保持一致（`local_music_scanner.dart` 的扩展名清单），
  /// 否则同一个 NAS 上的 APE/WMA 在本地能播、走 WebDAV 却根本列不出来。
  static const _audioExtensions = {
    'mp3',
    'flac',
    'm4a',
    'aac',
    'wav',
    'ogg',
    'opus',
    'wma',
    'ape',
    'aiff',
    'alac',
  };

  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'bmp'};

  /// 同目录图片按这个顺序挑一张当专辑封面。
  static const _artworkNames = {
    'cover': 0,
    'folder': 1,
    'front': 2,
    'album': 3,
    'albumart': 4,
    'artwork': 5,
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
    int limit = kNasLibraryLimit,
  }) async {
    final cap = limit < 1 ? kNasLibraryLimit : limit;
    final songs = <MusicItem>[];
    final pending = <Uri>[_rootUri(config)];
    final visitedDirectories = <String>{};
    final seenFiles = <String>{};
    while (pending.isNotEmpty && songs.length < cap) {
      final directory = pending.removeAt(0);
      final directoryKey = _withoutTrailingSlash(directory.path);
      if (!visitedDirectories.add(directoryKey)) continue;
      final response = await _propfind(config, secrets, directory, depth: '1');
      final entries = _parseResponses(
        config,
        response.data ?? '',
        directory,
      );
      // 目录里的封面图和 .lrc 侧车文件本来就在这次的 PROPFIND 结果里，
      // 顺带记下来可以零成本补上封面与歌词。
      final assets = _assetsOf(entries);
      for (final item in entries) {
        if (item.isDirectory) {
          if (_withoutTrailingSlash(item.uri.path) != directoryKey &&
              _isInRoot(config, item.uri)) {
            pending.add(item.uri.removeFragment());
          }
          continue;
        }
        final song = _songFromEntry(config, item, assets);
        if (song == null) continue;
        if (!seenFiles.add(song.songmid ?? song.id)) continue;
        songs.add(song);
        if (songs.length >= cap) break;
      }
    }
    return List<MusicItem>.unmodifiable(songs);
  }

  /// 供设置页的目录选择器用：列出 [path]（相对服务地址）下的子目录。
  Future<List<WebDavDirectory>> listDirectories(
    NasConfig config,
    NasSecrets secrets,
    String path,
  ) async {
    final uri = _serverUriAt(config, path);
    final response = await _propfind(config, secrets, uri, depth: '1');
    final entries = _parseResponses(config, response.data ?? '', uri, enforceRoot: false);
    final current = _withoutTrailingSlash(uri.path);
    final directories = <WebDavDirectory>[];
    for (final entry in entries) {
      if (!entry.isDirectory) continue;
      final entryPath = _withoutTrailingSlash(entry.uri.path);
      if (entryPath == current) continue;
      directories.add(
        WebDavDirectory(
          name: _displayNameOf(entry),
          path: _relativeToServer(config, entry.uri),
        ),
      );
    }
    directories.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return directories;
  }

  @override
  Future<List<MusicItem>> search(
    NasConfig config,
    NasSecrets secrets,
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final all = await getLibrarySongs(config, secrets, limit: kNasLibraryLimit);
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
  Map<String, String> artworkHeaders(NasConfig config, NasSecrets secrets) =>
      _authHeaders(config, secrets);

  @override
  Future<String?> getLyrics(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music,
  ) async {
    final url = music.meta?['lyricUrl']?.toString();
    if (url == null || url.isEmpty) return null;
    try {
      final response = await dio.get<dynamic>(
        url,
        options: Options(
          headers: _authHeaders(config, secrets),
          responseType: ResponseType.bytes,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final data = response.data;
      if (data is! List<int> || data.isEmpty) return null;
      final text = decodeLyricBytes(Uint8List.fromList(data)).trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  List<_WebDavEntry> _parseResponses(
    NasConfig config,
    String xml,
    Uri baseUri, {
    bool enforceRoot = true,
  }) {
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
        if (uri == null) continue;
        if (enforceRoot && !_isInRoot(config, uri)) continue;
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

  /// 只比路径前缀，不再要求 scheme/host/port 完全一致。
  ///
  /// 反向代理（Nextcloud、OpenList、群晖套件门户）经常返回用公网域名拼出来的
  /// 绝对 href，而用户填的是内网地址；按旧逻辑这些条目会被整批丢掉，表现为
  /// 「连上了但一首歌都没有」。
  bool _isInRoot(NasConfig config, Uri uri) {
    final rootPath = _withoutTrailingSlash(_rootUri(config).path);
    final path = _withoutTrailingSlash(uri.path);
    // 根目录就是 '/ 时，`$rootPath/` 会变成 '//'，前缀永远匹配不上。
    if (rootPath == '/' || rootPath.isEmpty) return true;
    return path == rootPath || path.startsWith('$rootPath/');
  }

  /// 服务地址本身（不含 rootPath），目录选择器从这里开始浏览。
  Uri _serverUri(NasConfig config) {
    final base = Uri.parse(config.baseUrl);
    final path = base.path.replaceFirst(RegExp(r'/+$'), '');
    return base.replace(path: path.isEmpty ? '/' : '$path/');
  }

  Uri _serverUriAt(NasConfig config, String relativePath) {
    final base = _serverUri(config);
    final clean = relativePath.trim().replaceFirst(RegExp(r'^/+'), '');
    if (clean.isEmpty) return base;
    return base.replace(
      path: '${base.path}$clean',
    );
  }

  String _relativeToServer(NasConfig config, Uri uri) {
    final basePath = _withoutTrailingSlash(_serverUri(config).path);
    final path = _withoutTrailingSlash(uri.path);
    if (basePath == '/' || basePath.isEmpty) return path;
    if (path == basePath) return '/';
    if (!path.startsWith('$basePath/')) return '/';
    return path.substring(basePath.length);
  }

  String _displayNameOf(_WebDavEntry entry) {
    final name = entry.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return _basename(entry.uri.path);
  }

  MusicItem? _songFromEntry(
    NasConfig config,
    _WebDavEntry entry,
    _DirAssets assets,
  ) {
    final extension = _extension(entry.uri.path);
    if (extension == null || !_audioExtensions.contains(extension)) return null;
    final name = entry.displayName?.trim().isNotEmpty == true
        ? entry.displayName!.trim()
        : _basename(entry.uri.path);
    final title = _titleFromFileName(name);
    final url = entry.uri.toString();
    final folders = _foldersFromRoot(config, entry.uri);
    // 常见布局是 …/艺术家/专辑/曲目；只有一层时把它当专辑，不要再硬当歌手。
    final album = folders.isNotEmpty ? folders.last : '';
    final singer = folders.length >= 2 ? folders[folders.length - 2] : '';
    final lyricUrl = assets.lyrics[_stemKey(name)];
    return MusicItem(
      id: url,
      name: title,
      singer: singer,
      album: album,
      artwork: assets.artworkUrl,
      source: kind.id,
      platform: kind.id,
      songmid: url,
      isPlayable: true,
      meta: {
        'webdavUrl': url,
        if (folders.isNotEmpty) 'folder': folders.join('/'),
        if (lyricUrl != null) 'lyricUrl': lyricUrl,
        'fileName': name,
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

  /// 目录内的封面图与同名 .lrc。这些条目本来就在同一次 PROPFIND 里，
  /// 不需要额外请求。
  _DirAssets _assetsOf(List<_WebDavEntry> entries) {
    String? artwork;
    var artworkRank = 999;
    final lyrics = <String, String>{};
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final name = _basename(entry.uri.path).toLowerCase();
      final dot = name.lastIndexOf('.');
      if (dot <= 0 || dot == name.length - 1) continue;
      final extension = name.substring(dot + 1);
      if (_imageExtensions.contains(extension)) {
        final stem = name.substring(0, dot);
        final rank = _artworkNames[stem] ?? 99;
        if (rank < artworkRank) {
          artworkRank = rank;
          artwork = entry.uri.toString();
        }
        continue;
      }
      if (extension == 'lrc') {
        lyrics[name.substring(0, dot)] = entry.uri.toString();
      }
    }
    return _DirAssets(artworkUrl: artwork, lyrics: lyrics);
  }

  /// 去掉扩展名和曲目序号。「01 - 晴天.flac」「03.晴天.mp3」都还原成「晴天」。
  String _titleFromFileName(String fileName) {
    final base = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final stripped = base.replaceFirst(
      RegExp(r'^\s*\d{1,3}\s*[-._)]\s*'),
      '',
    );
    final title = stripped.trim();
    if (title.isEmpty) return base.trim().isEmpty ? fileName : base.trim();
    return title;
  }

  /// 匹配 .lrc 用的键：小写、去扩展名。
  String _stemKey(String fileName) {
    final base = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return base.trim().toLowerCase();
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

class _DirAssets {
  const _DirAssets({this.artworkUrl, this.lyrics = const {}});

  final String? artworkUrl;

  /// 文件名（小写、无扩展名）→ .lrc 的绝对地址。
  final Map<String, String> lyrics;
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
