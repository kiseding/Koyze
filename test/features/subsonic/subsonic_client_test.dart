import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/network/music_source_service.dart';
import 'package:koyze/core/storage/secure_token_store.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/subsonic/domain/subsonic_auth.dart';
import 'package:koyze/features/subsonic/domain/subsonic_client.dart';
import 'package:koyze/features/subsonic/domain/subsonic_config.dart';
import 'package:koyze/features/subsonic/domain/subsonic_service.dart';
import 'package:koyze/features/subsonic/domain/subsonic_store.dart';
import 'package:koyze/features/subsonic/domain/subsonic_url.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryTokenStore implements SecureTokenStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Dio _okDio(Map<String, dynamic> Function(RequestOptions options) body) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: body(options),
          ),
        );
      },
    ),
  );
  return dio;
}

Map<String, dynamic> _ok(Map<String, dynamic> extra) => {
      'subsonic-response': {
        'status': 'ok',
        'version': '1.16.1',
        ...extra,
      },
    };

void main() {
  const config = SubsonicConfig(
    baseUrl: 'http://192.168.1.8:4533',
    username: 'alice',
  );

  test('token auth hashes password with salt', () {
    final params = subsonicAuthParams(
      username: 'alice',
      password: 'secret',
      salt: 'abc',
    );
    expect(params['u'], 'alice');
    expect(params['s'], 'abc');
    expect(params['t'], 'c42b93a1ac3b382e88071510296a96ce');
    expect(params.containsKey('p'), isFalse);
  });

  test('legacy auth sends plaintext password', () {
    final params = subsonicAuthParams(
      username: 'alice',
      password: 'secret',
      legacy: true,
    );
    expect(params['p'], 'secret');
    expect(params.containsKey('t'), isFalse);
  });

  test('server URL allows LAN HTTP and rejects credentials', () {
    expect(
      validateSubsonicServiceUrl('http://192.168.1.8:4533/'),
      'http://192.168.1.8:4533',
    );
    expect(
      () => validateSubsonicServiceUrl('http://alice:secret@192.168.1.8:4533'),
      throwsArgumentError,
    );
    expect(
      () => validateSubsonicServiceUrl('ftp://192.168.1.8'),
      throwsArgumentError,
    );
  });

  test('client ping unwraps OpenSubsonic envelope', () async {
    final client = SubsonicClient(
      dio: _okDio(
        (_) => _ok({'type': 'navidrome', 'openSubsonic': true}),
      ),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final result = await client.ping(config, 'secret');
    expect(result.ok, isTrue);
    expect(result.serverType, 'navidrome');
    expect(result.openSubsonic, isTrue);
  });

  test('library songs expand newest albums without using playlists', () async {
    final seen = <String>[];
    final client = SubsonicClient(
      dio: _okDio((options) {
        final path = options.uri.path;
        seen.add(path);
        if (path.endsWith('/getAlbumList2')) {
          expect(options.uri.queryParameters['type'], 'newest');
          return _ok({
            'albumList2': {
              'album': [
                {'id': 'al-1', 'name': 'Album'},
              ],
            },
          });
        }
        if (path.endsWith('/getAlbum')) {
          expect(options.uri.queryParameters['id'], 'al-1');
          return _ok({
            'album': {
              'song': [
                {
                  'id': '42',
                  'title': 'Song',
                  'artist': 'Artist',
                  'album': 'Album',
                  'duration': 180,
                  'coverArt': 'al-42',
                },
              ],
            },
          });
        }
        fail('unexpected $path');
      }),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final songs = await client.getLibrarySongs(config, 'secret', limit: 20);
    expect(songs, hasLength(1));
    expect(songs.single.name, 'Song');
    expect(songs.single.singer, 'Artist');
    expect(songs.single.source, 'subsonic');
    expect(seen.any((path) => path.endsWith('/getPlaylists')), isFalse);
    expect(seen.any((path) => path.endsWith('/getRandomSongs')), isFalse);
  });

  test('library songs fall back to random songs when albums are empty', () async {
    final client = SubsonicClient(
      dio: _okDio((options) {
        final path = options.uri.path;
        if (path.endsWith('/getAlbumList2')) {
          return _ok({'albumList2': <String, dynamic>{}});
        }
        if (path.endsWith('/getRandomSongs')) {
          return _ok({
            'randomSongs': {
              'song': [
                {
                  'id': '99',
                  'title': 'Random',
                  'artist': 'Someone',
                  'album': 'Misc',
                  'duration': 90,
                },
              ],
            },
          });
        }
        fail('unexpected $path');
      }),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final songs = await client.getLibrarySongs(config, 'secret', limit: 20);
    expect(songs.single.id, '99');
    expect(songs.single.name, 'Random');
  });

  test('client maps playlist songs and keeps LAN cover URL', () async {
    final client = SubsonicClient(
      dio: _okDio(
        (_) => _ok({
          'playlist': {
            'entry': {
              'id': '42',
              'title': 'Song',
              'artist': 'Artist',
              'album': 'Album',
              'duration': 180,
              'coverArt': 'al-42',
            },
          },
        }),
      ),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final songs = await client.getPlaylistSongs(config, 'secret', 'pl-1');
    expect(songs, hasLength(1));
    expect(songs.single.source, 'subsonic');
    expect(songs.single.platform, 'subsonic');
    expect(songs.single.artwork, contains('http://192.168.1.8:4533/rest/getCoverArt'));
    expect(songs.single.artwork, contains('id=al-42'));
  });

  test('stream URL stays on original HTTP scheme', () {
    final client = SubsonicClient(saltGenerator: () => 'fixedsalt12');
    addTearDown(client.dispose);
    final url = client.streamUrl(config, 'secret', '42', quality: '320k');
    expect(url.startsWith('http://192.168.1.8:4533/rest/stream?'), isTrue);
    expect(url, contains('format=raw'));
    expect(url, isNot(contains('maxBitRate=')));
    expect(url, contains('id=42'));
  });

  test('connect stores credentials and resolves play URL', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SubsonicStore(
      storage: () async => StorageService.forTesting(prefs),
      tokenStore: _MemoryTokenStore(),
    );
    final client = SubsonicClient(
      dio: _okDio((_) => _ok({'type': 'navidrome', 'openSubsonic': true})),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final service = SubsonicService(store: store, client: client);
    addTearDown(service.dispose);

    final ping = await service.connect(
      baseUrl: 'http://192.168.1.8:4533/',
      username: 'alice',
      password: 'secret',
    );
    expect(ping.ok, isTrue);
    expect(service.isConnected, isTrue);

    final url = await service.getPlayUrl(
      MusicItem(
        id: '42',
        name: 'Song',
        singer: 'Artist',
        source: 'subsonic',
        platform: 'subsonic',
        songmid: '42',
      ),
      quality: 'flac',
    );
    expect(url, contains('/rest/stream?'));
    expect(url, contains('format=raw'));
  });

  test('MusicSourceService resolves Subsonic without built-in fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SubsonicStore(
      storage: () async => StorageService.forTesting(prefs),
      tokenStore: _MemoryTokenStore(),
    );
    final client = SubsonicClient(
      dio: _okDio((_) => _ok({'type': 'navidrome'})),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final subsonic = SubsonicService(store: store, client: client);
    addTearDown(subsonic.dispose);
    await subsonic.connect(
      baseUrl: 'http://192.168.1.8:4533',
      username: 'alice',
      password: 'secret',
    );

    final source = MusicSourceService(
      CustomSourceService(),
      subsonicService: subsonic,
    );
    addTearDown(source.dispose);
    final result = await source.resolvePlayableUrl(
      MusicItem(
        id: '42',
        name: 'Song',
        singer: 'Artist',
        source: 'subsonic',
        platform: 'subsonic',
        songmid: '42',
      ),
      preferredQuality: '320k',
    );
    expect(result, isNotNull);
    expect(result!.platform, 'subsonic');
    expect(result.url, contains('http://192.168.1.8:4533/rest/stream'));
  });

  test('Subsonic parseSong keeps native bitrate in meta', () {
    final client = SubsonicClient(saltGenerator: () => 'fixedsalt12');
    addTearDown(client.dispose);
    final song = client.parseSong(config, 'secret', {
      'id': '42',
      'title': 'Song',
      'artist': 'Artist',
      'suffix': 'mp3',
      'contentType': 'audio/mpeg',
      'bitRate': 192,
    });
    expect(song.meta?['bitRate'], 192);
    expect(song.meta?['suffix'], 'mp3');
    expect(song.meta?['contentType'], 'audio/mpeg');
  });

  test('MusicSourceService reports native Subsonic bitrate, not requested', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SubsonicStore(
      storage: () async => StorageService.forTesting(prefs),
      tokenStore: _MemoryTokenStore(),
    );
    final client = SubsonicClient(
      dio: _okDio((_) => _ok({'type': 'navidrome'})),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final subsonic = SubsonicService(store: store, client: client);
    addTearDown(subsonic.dispose);
    await subsonic.connect(
      baseUrl: 'http://192.168.1.8:4533',
      username: 'alice',
      password: 'secret',
    );

    final source = MusicSourceService(
      CustomSourceService(),
      subsonicService: subsonic,
    );
    addTearDown(source.dispose);
    final result = await source.resolvePlayableUrl(
      MusicItem(
        id: '42',
        name: 'Song',
        singer: 'Artist',
        source: 'subsonic',
        platform: 'subsonic',
        songmid: '42',
        meta: {
          'bitRate': 192,
          'suffix': 'mp3',
          'contentType': 'audio/mpeg',
        },
      ),
      preferredQuality: '320k',
    );
    expect(result, isNotNull);
    expect(result!.requestedQuality, '320k');
    expect(result.actualQuality, '192k');
  });

  test('server URL infers HTTP for LAN hosts and HTTPS for domains', () {
    expect(
      validateSubsonicServiceUrl('192.168.1.8:4533'),
      'http://192.168.1.8:4533',
    );
    expect(
      validateSubsonicServiceUrl('navidrome.local:4533/'),
      'http://navidrome.local:4533',
    );
    expect(
      validateSubsonicServiceUrl('localhost:4533/subsonic/'),
      'http://localhost:4533/subsonic',
    );
    expect(
      validateSubsonicServiceUrl('music.example.com'),
      'https://music.example.com',
    );
    expect(
      () => validateSubsonicServiceUrl('https://music.example.com/?x=1'),
      throwsArgumentError,
    );
  });

  test('failed ping does not persist credentials', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tokens = _MemoryTokenStore();
    final store = SubsonicStore(
      storage: () async => StorageService.forTesting(prefs),
      tokenStore: tokens,
    );
    final client = SubsonicClient(
      dio: _okDio(
        (_) => {
          'subsonic-response': {
            'status': 'failed',
            'error': {'code': 40, 'message': 'Wrong username or password'},
          },
        },
      ),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final service = SubsonicService(store: store, client: client);
    addTearDown(service.dispose);

    final ping = await service.connect(
      baseUrl: '192.168.1.8:4533',
      username: 'alice',
      password: 'wrong',
    );
    expect(ping.ok, isFalse);
    expect(ping.error, 'Wrong username or password');
    expect(service.isConnected, isFalse);
    expect(tokens.values, isEmpty);
    expect(prefs.getString(subsonicConfigPrefsKey), isNull);
  });

  test('disconnect and disable both stop playback resolution', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SubsonicStore(
      storage: () async => StorageService.forTesting(prefs),
      tokenStore: _MemoryTokenStore(),
    );
    final client = SubsonicClient(
      dio: _okDio((_) => _ok({'type': 'navidrome'})),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final service = SubsonicService(store: store, client: client);
    addTearDown(service.dispose);
    await service.connect(
      baseUrl: 'http://192.168.1.8:4533',
      username: 'alice',
      password: 'secret',
    );

    final song = MusicItem(
      id: '42',
      name: 'Song',
      singer: 'Artist',
      source: 'subsonic',
      platform: 'subsonic',
      songmid: '42',
    );
    expect(await service.getPlayUrl(song), isNotNull);

    await service.setEnabled(false);
    expect(service.isConnected, isFalse);
    expect(await service.getPlayUrl(song), isNull);
    expect(await service.search('Song'), isEmpty);

    await service.setEnabled(true);
    expect(service.isConnected, isTrue);

    await service.disconnect();
    expect(service.isConnected, isFalse);
    expect(await service.getPlayUrl(song), isNull);
    expect(prefs.getString(subsonicConfigPrefsKey), isNotNull);
  });

  test('lyrics survive missing OpenSubsonic endpoint and missing lyrics', () async {
    final client = SubsonicClient(
      dio: _okDio((options) {
        if (options.uri.path.endsWith('/getLyricsBySongId')) {
          return {
            'subsonic-response': {
              'status': 'failed',
              'error': {'code': 0, 'message': 'not found'},
            },
          };
        }
        if (options.uri.path.endsWith('/getLyrics')) {
          return _ok({
            'lyrics': {'value': '[00:01.00]hello'},
          });
        }
        return _ok({});
      }),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(client.dispose);
    final lyrics = await client.getLyrics(
      config,
      'secret',
      MusicItem(
        id: '42',
        name: 'Song',
        singer: 'Artist',
        source: 'subsonic',
      ),
    );
    expect(lyrics, '[00:01.00]hello');

    final emptyClient = SubsonicClient(
      dio: _okDio(
        (_) => {
          'subsonic-response': {
            'status': 'failed',
            'error': {'code': 70, 'message': 'not found'},
          },
        },
      ),
      saltGenerator: () => 'fixedsalt12',
    );
    addTearDown(emptyClient.dispose);
    expect(
      await emptyClient.getLyrics(
        config,
        'secret',
        MusicItem(
          id: '42',
          name: 'Song',
          singer: 'Artist',
          source: 'subsonic',
        ),
      ),
      isNull,
    );
  });

  test('MusicSourceService does not leak Subsonic into built-in play URLs', () async {
    SharedPreferences.setMockInitialValues({});
    final source = MusicSourceService(CustomSourceService());
    addTearDown(source.dispose);
    final result = await source.resolvePlayableUrl(
      MusicItem(
        id: '42',
        name: 'Song',
        singer: 'Artist',
        source: 'subsonic',
        platform: 'subsonic',
        songmid: '42',
      ),
      preferredQuality: '320k',
    );
    // 播放仍走 NAS / Subsonic。歌词在服务器没有时可以回退内置平台，
    // 那是刮削路径，不在这条测例里。
    expect(result, isNull);
  });

  test('search skips empty queries and missing session', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = SubsonicService(
      store: SubsonicStore(
        storage: () async => StorageService.forTesting(prefs),
        tokenStore: _MemoryTokenStore(),
      ),
      client: SubsonicClient(saltGenerator: () => 'fixedsalt12'),
    );
    addTearDown(service.dispose);
    expect(await service.search('   '), isEmpty);
    expect(await service.search('hello'), isEmpty);
  });
}
