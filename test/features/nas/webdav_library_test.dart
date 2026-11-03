import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/nas/domain/nas_config.dart';
import 'package:koyze/features/nas/domain/nas_kind.dart';
import 'package:koyze/features/nas/domain/webdav_client.dart';

const _config = NasConfig(
  kind: NasKind.webdav,
  baseUrl: 'http://nas.local:8080',
  username: 'alice',
  rootPath: '/music',
);

const _secrets = NasSecrets(password: 'secret');

String _nameOf(String href) {
  final segments = href.split('/').where((segment) => segment.isNotEmpty);
  if (segments.isEmpty) return '/';
  try {
    return Uri.decodeComponent(segments.last);
  } on ArgumentError {
    return segments.last;
  }
}

String _entry(String href, {bool dir = false, int? size, String? type}) {
  return '''
  <d:response>
    <d:href>$href</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype>${dir ? '<d:collection/>' : ''}</d:resourcetype>
        <d:displayname>${_nameOf(href)}</d:displayname>
        ${size == null ? '' : '<d:getcontentlength>$size</d:getcontentlength>'}
        ${type == null ? '' : '<d:getcontenttype>$type</d:getcontenttype>'}
        <d:getlastmodified>Sun, 25 Oct 2026 10:00:00 GMT</d:getlastmodified>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>''';
}

String _multistatus(List<String> entries) =>
    '<?xml version="1.0" encoding="utf-8"?><d:multistatus xmlns:d="DAV:">'
    '${entries.join()}</d:multistatus>';

final _rootXml = _multistatus([
  _entry('/music/', dir: true),
  _entry('/music/周杰伦/', dir: true),
  _entry('/music/readme.txt', size: 12, type: 'text/plain'),
  _entry('/music/cover.jpg', size: 4096, type: 'image/jpeg'),
  _entry('/music/top.ape', size: 1024, type: 'audio/ape'),
]);

final _artistXml = _multistatus([
  _entry('/music/周杰伦/', dir: true),
  _entry('/music/周杰伦/范特西/', dir: true),
]);

final _albumXml = _multistatus([
  _entry('/music/周杰伦/范特西/', dir: true),
  _entry(
    '/music/周杰伦/范特西/01%20-%20%E6%99%B4%E5%A4%A9.flac',
    size: 2048,
    type: 'audio/flac',
  ),
  _entry('/music/周杰伦/范特西/folder.jpg', size: 512, type: 'image/jpeg'),
  _entry('/music/周杰伦/范特西/01%20-%20%E6%99%B4%E5%A4%A9.lrc', size: 90),
]);

Dio _fakeDio(
  Map<String, String> xmlByPath, {
  List<int>? lyricBytes,
  void Function(RequestOptions options)? onRequest,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onRequest?.call(options);
        // Dio 会把中文路径转义，fixture 用可读路径做键。
        final path = Uri.decodeComponent(Uri.parse(options.uri.toString()).path);
        if (options.method == 'GET') {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: lyricBytes ?? const <int>[],
            ),
          );
          return;
        }
        final body = xmlByPath[path];
        if (body == null) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 404,
              ),
              type: DioExceptionType.badResponse,
            ),
          );
          return;
        }
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 207,
            data: body,
            headers: Headers.fromMap({
              'server': ['nginx'],
            }),
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  group('WebDAV library enrichment', () {
    test('picks folder artwork and sidecar lyrics from the same listing',
        () async {
      final requests = <String>[];
      final client = WebDavNasClient(
        dio: _fakeDio(
          {
            '/music/': _rootXml,
            '/music/周杰伦/': _artistXml,
            '/music/周杰伦/范特西/': _albumXml,
          },
          onRequest: (options) =>
              requests.add('${options.method} ${options.uri.path}'),
        ),
      );
      addTearDown(client.dispose);

      final songs = await client.getLibrarySongs(_config, _secrets);

      expect(songs, hasLength(2));
      final qingTian = songs.firstWhere((song) => song.name == '晴天');
      expect(qingTian.singer, '周杰伦');
      expect(qingTian.album, '范特西');
      expect(qingTian.artwork, contains('folder.jpg'));
      expect(
        qingTian.meta?['lyricUrl'],
        contains(Uri.encodeComponent('01 - 晴天.lrc')),
      );

      // 根目录的 cover.jpg 也在同一次 PROPFIND 里，直接复用给根目录的歌。
      final top = songs.firstWhere((song) => song.name == 'top');
      expect(top.artwork, contains('cover.jpg'));
      expect(top.meta?['lyricUrl'], isNull);

      // 每层目录只发一次 PROPFIND，不应为了封面/歌词额外请求。
      expect(requests.where((line) => line.startsWith('PROPFIND')), hasLength(3));
      expect(requests.every((line) => line.startsWith('PROPFIND')), isTrue);
    });

    test('lists APE/WMA which the local scanner already supports', () async {
      final client = WebDavNasClient(
        dio: _fakeDio({
          '/music/': _rootXml,
          '/music/周杰伦/': _artistXml,
          '/music/周杰伦/范特西/': _albumXml,
        }),
      );
      addTearDown(client.dispose);

      final songs = await client.getLibrarySongs(_config, _secrets);

      expect(songs.map((song) => song.meta?['suffix']), contains('ape'));
    });

    test('keeps a file that lives on the proxy host from another origin',
        () async {
      final xml = _multistatus([
        _entry('/music/', dir: true),
        _entry('https://media.example.com/music/proxied.mp3', size: 10),
      ]);
      final client = WebDavNasClient(dio: _fakeDio({'/music/': xml}));
      addTearDown(client.dispose);

      final songs = await client.getLibrarySongs(_config, _secrets);

      expect(songs, hasLength(1));
      expect(songs.single.name, 'proxied');
    });

    test('fetches sidecar lyrics with the connection headers', () async {
      RequestOptions? lyricRequest;
      final client = WebDavNasClient(
        dio: _fakeDio(
          {
            '/music/': _rootXml,
            '/music/周杰伦/': _artistXml,
            '/music/周杰伦/范特西/': _albumXml,
          },
          lyricBytes: utf8.encode('[00:01.00]晴天'),
          onRequest: (options) {
            if (options.method == 'GET') lyricRequest = options;
          },
        ),
      );
      addTearDown(client.dispose);

      final songs = await client.getLibrarySongs(_config, _secrets);
      final song = songs.firstWhere((item) => item.name == '晴天');

      final lyric = await client.getLyrics(_config, _secrets, song);

      expect(lyric, '[00:01.00]晴天');
      expect(
        lyricRequest?.headers['Authorization'],
        'Basic ${base64.encode(utf8.encode('alice:secret'))}',
      );
    });

    test('lists subdirectories relative to the server root', () async {
      final xml = _multistatus([
        _entry('/', dir: true),
        _entry('/music/', dir: true),
        _entry('/photo/', dir: true),
        _entry('/notes.txt', size: 1),
      ]);
      final client = WebDavNasClient(dio: _fakeDio({'/': xml}));
      addTearDown(client.dispose);

      final directories = await client.listDirectories(_config, _secrets, '/');

      expect(directories.map((dir) => dir.path), containsAll(['/music', '/photo']));
      expect(directories.map((dir) => dir.name), containsAll(['music', 'photo']));
    });

    test('directory picker ignores the configured root filter', () async {
      final xml = _multistatus([
        _entry('/dav/', dir: true),
        _entry('/dav/music/', dir: true),
        _entry('/dav/backup/', dir: true),
      ]);
      final client = WebDavNasClient(dio: _fakeDio({'/dav/': xml}));
      addTearDown(client.dispose);

      const config = NasConfig(
        kind: NasKind.webdav,
        baseUrl: 'http://nas.local:8080/dav',
        username: 'alice',
        rootPath: '/music',
      );

      final directories = await client.listDirectories(config, _secrets, '/');

      expect(
        directories.map((dir) => dir.path),
        containsAll(['/music', '/backup']),
      );
    });
  });
}
