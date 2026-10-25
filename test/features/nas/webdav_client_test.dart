import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/nas/domain/nas_config.dart';
import 'package:koyze/features/nas/domain/nas_kind.dart';
import 'package:koyze/features/nas/domain/nas_service.dart';
import 'package:koyze/features/nas/domain/nas_store.dart';
import 'package:koyze/features/nas/domain/nas_url.dart';
import 'package:koyze/features/nas/domain/webdav_client.dart';
import 'package:koyze/core/storage/secure_token_store.dart';
import 'package:koyze/features/player/domain/music_item.dart';

const _basicConfig = NasConfig(
  kind: NasKind.webdav,
  baseUrl: 'http://nas.local:8080',
  username: 'alice',
  rootPath: '/music',
);

const _rootResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/music/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
        <d:displayname>music</d:displayname>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/music/Artist%20One/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
        <d:displayname>Artist One</d:displayname>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/music/readme.txt</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getcontentlength>12</d:getcontentlength>
        <d:getcontenttype>text/plain</d:getcontenttype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/music/top.flac</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getcontentlength>1024</d:getcontentlength>
        <d:getcontenttype>audio/flac</d:getcontenttype>
        <d:getlastmodified>Sun, 25 Oct 2026 10:00:00 GMT</d:getlastmodified>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

const _artistResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/music/Artist%20One/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
        <d:displayname>Artist One</d:displayname>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/music/Artist%20One/song%20one.mp3</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getcontentlength>2048</d:getcontentlength>
        <d:getcontenttype>audio/mpeg</d:getcontenttype>
        <d:getlastmodified>Sun, 25 Oct 2026 11:00:00 GMT</d:getlastmodified>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/music/Artist%20One/cover.jpg</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getcontentlength>4096</d:getcontentlength>
        <d:getcontenttype>image/jpeg</d:getcontenttype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

Dio _propfindDio(
  Map<String, String> responses, {
  void Function(RequestOptions options)? onRequest,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onRequest?.call(options);
        final path = Uri.parse(options.uri.toString()).path;
        final body = responses[path];
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

class _MemoryTokenStore implements SecureTokenStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  group('WebDAV config', () {
    test('NasKind exposes WebDAV labels and routes', () {
      expect(NasKind.webdav.title, 'WebDAV');
      expect(NasKind.webdav.settingsRoute, '/webdav-settings');
      expect(NasKind.webdav.playlistRoute('a/b'), '/webdav/playlist/a%2Fb');
      expect(nasKindIds, contains('webdav'));
      expect(isNasMusic('webdav', 'webdav'), isTrue);
      expect(nasKindOf(null, 'webdav'), NasKind.webdav);
      expect(canonicalSearchPlatform('webdav'), 'subsonic');
    });

    test('root path normalization rejects URLs', () {
      expect(normalizeNasRootPath(null), '/');
      expect(normalizeNasRootPath(''), '/');
      expect(normalizeNasRootPath('/'), '/');
      expect(normalizeNasRootPath('music'), '/music');
      expect(normalizeNasRootPath('/music/'), '/music');
      expect(normalizeNasRootPath('//a//b//'), '/a//b');
      expect(
        () => normalizeNasRootPath('https://nas.local/music'),
        throwsArgumentError,
      );
    });

    test('config JSON keeps non-sensitive WebDAV fields only', () {
      const config = NasConfig(
        kind: NasKind.webdav,
        baseUrl: 'http://nas.local:8080',
        username: 'alice',
        rootPath: '/music',
        authMethod: NasAuthMethod.bearer,
      );
      final json = config.toJson();
      expect(json['rootPath'], '/music');
      expect(json['authMethod'], 'bearer');
      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('token'), isFalse);
      final restored = NasConfig.fromJson(NasKind.webdav, json);
      expect(restored.rootPath, '/music');
      expect(restored.authMethod, NasAuthMethod.bearer);
    });
  });

  group('WebDavNasClient', () {
    test('connects with Basic auth and probes root', () async {
      RequestOptions? seen;
      final client = WebDavNasClient(
        dio: _propfindDio({
          '/music/': _rootResponse,
        }, onRequest: (options) => seen = options),
      );
      addTearDown(client.dispose);

      final result = await client.connect(
        _basicConfig,
        const NasSecrets(password: 'secret'),
      );

      expect(result.ok, isTrue);
      expect(result.serverType, 'WebDAV');
      expect(result.serverVersion, 'nginx');
      expect(seen?.method, 'PROPFIND');
      expect(seen?.headers['Depth'], '0');
      final expected = 'Basic ${base64.encode(utf8.encode('alice:secret'))}';
      expect(seen?.headers['Authorization'], expected);
      expect(seen?.uri.path, '/music/');
    });

    test('connects with Bearer token', () async {
      RequestOptions? seen;
      final client = WebDavNasClient(
        dio: _propfindDio({
          '/': _rootResponse,
        }, onRequest: (options) => seen = options),
      );
      addTearDown(client.dispose);

      final result = await client.connect(
        const NasConfig(
          kind: NasKind.webdav,
          baseUrl: 'https://dav.example.com',
          username: '',
          authMethod: NasAuthMethod.bearer,
        ),
        const NasSecrets(token: 'tok-123'),
      );

      expect(result.ok, isTrue);
      expect(seen?.headers['Authorization'], 'Bearer tok-123');
    });

    test('reports auth failure without leaking credentials', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 401,
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );
      final client = WebDavNasClient(dio: dio);
      addTearDown(client.dispose);

      final result = await client.connect(
        _basicConfig,
        const NasSecrets(password: 'top-secret'),
      );

      expect(result.ok, isFalse);
      expect(result.error, contains('WebDAV'));
      expect(result.error, isNot(contains('top-secret')));
    });

    test('scans recursively and filters audio files', () async {
      final requests = <String>[];
      final client = WebDavNasClient(
        dio: _propfindDio(
          {'/music/': _rootResponse, '/music/Artist%20One/': _artistResponse},
          onRequest: (options) => requests.add(
            '${options.headers['Depth']} ${Uri.parse(options.uri.toString()).path}',
          ),
        ),
      );
      addTearDown(client.dispose);

      final songs = await client.getLibrarySongs(
        _basicConfig,
        const NasSecrets(password: 'secret'),
      );

      expect(songs, hasLength(2));
      expect(songs.map((song) => song.name), containsAll(['top', 'song one']));
      expect(songs.every((song) => song.platform == 'webdav'), isTrue);
      expect(songs.every((song) => song.source == 'webdav'), isTrue);
      expect(requests, contains('1 /music/'));
      expect(requests, contains('1 /music/Artist%20One/'));
      expect(
        songs.map((song) => song.meta?['suffix']),
        containsAll(['flac', 'mp3']),
      );
      final flac = songs.firstWhere((song) => song.meta?['suffix'] == 'flac');
      expect(flac.meta?['fileSize'], 1024);
      expect(flac.meta?['contentType'], 'audio/flac');
      expect(flac.duration, Duration.zero);
    });

    test('stream result carries runtime headers and trusted flag', () async {
      final client = WebDavNasClient(dio: Dio());
      addTearDown(client.dispose);

      final music = MusicItem(
        id: 'http://nas.local:8080/music/a.flac',
        name: 'a',
        singer: '',
        source: 'webdav',
        platform: 'webdav',
        songmid: 'http://nas.local:8080/music/a.flac',
        meta: const {'webdavUrl': 'http://nas.local:8080/music/a.flac'},
      );

      final result = await client.streamResult(
        _basicConfig,
        const NasSecrets(password: 'secret'),
        music,
        quality: '320k',
      );

      expect(result.url, 'http://nas.local:8080/music/a.flac');
      expect(result.trustedNetwork, isTrue);
      expect(
        result.headers['Authorization'],
        'Basic ${base64.encode(utf8.encode('alice:secret'))}',
      );
      expect(result.url, isNot(contains('secret')));
    });

    test('search filters scanned library by name, artist, album', () async {
      final client = WebDavNasClient(
        dio: _propfindDio({
          '/music/': _rootResponse,
          '/music/Artist%20One/': _artistResponse,
        }),
      );
      addTearDown(client.dispose);

      final matches = await client.search(
        _basicConfig,
        const NasSecrets(password: 'secret'),
        'artist',
        limit: 10,
      );

      expect(matches, hasLength(1));
      expect(matches.single.name, 'song one');
    });

    test('rejects XML that is not a multistatus document', () async {
      final client = WebDavNasClient(
        dio: _propfindDio({'/music/': '<not-xml'}),
      );
      addTearDown(client.dispose);

      expect(
        () => client.getLibrarySongs(
          _basicConfig,
          const NasSecrets(password: 'secret'),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('NasService WebDAV persistence', () {
    test('stores auth method and root path but not credentials', () async {
      final tokens = _MemoryTokenStore();
      final store = _FakeNasStore(tokens: tokens);
      final service = NasService(
        kind: NasKind.webdav,
        store: store,
        client: WebDavNasClient(dio: _propfindDio({'/music/': _rootResponse})),
      );
      addTearDown(service.dispose);

      final result = await service.connect(
        baseUrl: 'http://nas.local:8080',
        username: 'alice',
        password: 'secret',
        rootPath: '/music',
      );

      expect(result.ok, isTrue);
      expect(service.config.rootPath, '/music');
      expect(service.config.authMethod, NasAuthMethod.basic);
      expect(store.savedConfig!.toJson().containsKey('password'), isFalse);
      expect(tokens.values.values, contains('secret'));
      expect(service.isConnected, isTrue);
    });
  });
}

class _FakeNasStore extends NasStore {
  _FakeNasStore({required this.tokens})
    : super(kind: NasKind.webdav, tokenStore: tokens);

  final _MemoryTokenStore tokens;
  NasConfig? savedConfig;

  @override
  Future<NasConfig> loadConfig() async => NasConfig.empty(NasKind.webdav);

  @override
  Future<void> saveConfig(NasConfig config) async => savedConfig = config;

  @override
  Future<NasSecrets> loadSecrets(String baseUrl) async => const NasSecrets();

  @override
  Future<void> saveSecrets(String baseUrl, NasSecrets secrets) async {
    if (secrets.hasPassword) {
      await tokens.write('pwd', secrets.password!);
    }
    if (secrets.hasToken) {
      await tokens.write('tok', secrets.token!);
    }
  }

  @override
  Future<void> deleteSecrets(String baseUrl) async {}
}
