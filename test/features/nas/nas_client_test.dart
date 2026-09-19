import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/network/music_source_service.dart';
import 'package:koyze/core/storage/secure_token_store.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/nas/domain/audiostation_client.dart';
import 'package:koyze/features/nas/domain/mediabrowser_client.dart';
import 'package:koyze/features/nas/domain/nas_config.dart';
import 'package:koyze/features/nas/domain/nas_kind.dart';
import 'package:koyze/features/nas/domain/nas_service.dart';
import 'package:koyze/features/nas/domain/nas_store.dart';
import 'package:koyze/features/nas/domain/nas_url.dart';
import 'package:koyze/features/nas/domain/plex_client.dart';
import 'package:koyze/features/nas/domain/self_hosted_kind.dart';
import 'package:koyze/features/player/domain/music_item.dart';
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

Dio _okDio(dynamic Function(RequestOptions options) body) {
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

void main() {
  test('NasKind routes and labels stay stable', () {
    expect(NasKind.emby.settingsRoute, '/emby-settings');
    expect(NasKind.jellyfin.routePrefix, '/jellyfin');
    expect(NasKind.plex.playlistRoute('ab/c'), '/plex/playlist/ab%2Fc');
    expect(NasKind.audiostation.shortSearchLabel, '群晖');
    expect(NasKind.emby.urlHint, '192.168.1.8:8096');
    expect(NasKind.plex.urlHint, '192.168.1.8:32400');
    expect(NasKind.audiostation.urlHint, '192.168.1.8:5000');
    expect(NasKind.tryParse('jellyfin'), NasKind.jellyfin);
    expect(isNasMusic('emby', 'emby'), isTrue);
    expect(isNasMusic('subsonic', 'subsonic'), isFalse);
    expect(nasKindOf('plex', null), NasKind.plex);
    expect(allowedSearchPlatforms, containsAll(['emby', 'subsonic', 'tx']));
    expect(SelfHostedKind.fromNas(NasKind.emby), SelfHostedKind.emby);
    expect(SelfHostedKind.subsonic.nasKind, isNull);
    expect(SelfHostedKind.audiostation.chipLabel, '群晖');
    expect(SelfHostedKind.emby.urlHint, '192.168.1.8:8096');
    expect(SelfHostedKind.values, hasLength(5));
  });

  test('Emby client authenticates and maps playlist songs', () async {
    final client = EmbyNasClient(
      dio: _okDio((options) {
        if (options.path.endsWith('/Users/AuthenticateByName')) {
          return {
            'AccessToken': 'emby-token',
            'User': {'Id': 'user-1'},
          };
        }
        if (options.path.contains('/System/Info/Public')) {
          return {'Version': '4.8.0'};
        }
        if (options.path.endsWith('/Users/user-1/Items') &&
            options.queryParameters['IncludeItemTypes'] == 'Playlist') {
          return {
            'Items': [
              {'Id': 'pl-1', 'Name': 'Favorites', 'ChildCount': 1},
            ],
          };
        }
        return {
          'Items': [
            {
              'Id': '42',
              'Name': 'Song',
              'AlbumArtist': 'Artist',
              'Album': 'Album',
              'RunTimeTicks': 1800000000,
            },
          ],
        };
      }),
    );
    addTearDown(client.dispose);

    const config = NasConfig(
      kind: NasKind.emby,
      baseUrl: 'http://192.168.1.8:8096',
      username: 'alice',
      userId: 'user-1',
    );
    const secrets = NasSecrets(password: 'secret', token: 'emby-token');
    final ping = await client.connect(config, const NasSecrets(password: 'secret'));
    expect(ping.ok, isTrue);
    expect(ping.token, 'emby-token');
    expect(ping.userId, 'user-1');

    final playlists = await client.getPlaylists(config, secrets);
    expect(playlists.single.id, 'pl-1');

    final songs = await client.getPlaylistSongs(config, secrets, 'pl-1');
    expect(songs, hasLength(1));
    expect(songs.single.source, 'emby');
    expect(songs.single.platform, 'emby');
    expect(songs.single.artwork, contains('http://192.168.1.8:8096/Items/42/Images/Primary'));
    expect(
      client.streamUrl(config, secrets, songs.single, quality: '320k'),
      contains('/Audio/42/stream?'),
    );
  });

  test('Jellyfin playlist songs use Playlists endpoint', () async {
    var sawPlaylistItems = false;
    final client = JellyfinNasClient(
      dio: _okDio((options) {
        if (options.path.contains('/Playlists/pl-1/Items')) {
          sawPlaylistItems = true;
          return {
            'Items': [
              {'Id': '99', 'Name': 'Track', 'AlbumArtist': 'A'},
            ],
          };
        }
        return {'Items': <dynamic>[]};
      }),
    );
    addTearDown(client.dispose);
    const config = NasConfig(
      kind: NasKind.jellyfin,
      baseUrl: 'http://192.168.1.8:8096',
      username: 'alice',
      userId: 'user-1',
    );
    final songs = await client.getPlaylistSongs(
      config,
      const NasSecrets(token: 'jf-token'),
      'pl-1',
    );
    expect(sawPlaylistItems, isTrue);
    expect(songs.single.id, '99');
    expect(songs.single.source, 'jellyfin');
  });

  test('Plex token-only connect skips plex.tv login', () async {
    var sawSignin = false;
    final client = PlexNasClient(
      dio: _okDio((options) {
        if (options.path.contains('plex.tv')) {
          sawSignin = true;
          return {'authToken': 'should-not-use'};
        }
        return {
          'MediaContainer': {'version': '1.40.0'},
        };
      }),
    );
    addTearDown(client.dispose);
    final ping = await client.connect(
      const NasConfig(
        kind: NasKind.plex,
        baseUrl: 'http://192.168.1.8:32400',
        username: '',
      ),
      const NasSecrets(token: 'plex-token'),
    );
    expect(ping.ok, isTrue);
    expect(sawSignin, isFalse);
    expect(ping.token, 'plex-token');
  });

  test('Audio Station login stores sid and keeps LAN stream URL', () async {
    final client = AudioStationNasClient(
      dio: _okDio((options) {
        if (options.path.endsWith('/webapi/auth.cgi')) {
          return {
            'success': true,
            'data': {'sid': 'sid-1'},
          };
        }
        if (options.path.contains('playlist.cgi')) {
          if (options.queryParameters['method']?.toString() == 'getinfo') {
            return {
              'success': true,
              'data': {
                'playlists': [
                  {
                    'id': 'pl-1',
                    'additional': {
                      'songs': [
                        {
                          'id': 'song-1',
                          'additional': {
                            'song_tag': {
                              'title': 'Song',
                              'artist': 'Artist',
                              'album': 'Album',
                            },
                            'song_audio': {'duration': 180},
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            };
          }
          return {
            'success': true,
            'data': {
              'playlists': [
                {'id': 'pl-1', 'name': 'My Mix', 'songs': 1},
              ],
            },
          };
        }
        return {'success': true, 'data': {}};
      }),
    );
    addTearDown(client.dispose);
    const config = NasConfig(
      kind: NasKind.audiostation,
      baseUrl: 'http://192.168.1.8:5000',
      username: 'alice',
    );
    final ping = await client.connect(
      config,
      const NasSecrets(password: 'secret'),
    );
    expect(ping.ok, isTrue);
    expect(ping.token, 'sid-1');
    const secrets = NasSecrets(token: 'sid-1');
    final songs = await client.getPlaylistSongs(config, secrets, 'pl-1');
    expect(songs.single.source, 'audiostation');
    final url = client.streamUrl(config, secrets, songs.single, quality: 'flac');
    expect(url.startsWith('http://192.168.1.8:5000/webapi/AudioStation/stream.cgi'), isTrue);
  });

  test('NasService persists credentials and MusicSourceService resolves Emby', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = NasStore(
      kind: NasKind.emby,
      storage: () async => StorageService.forTesting(prefs),
      tokenStore: _MemoryTokenStore(),
    );
    final client = EmbyNasClient(
      dio: _okDio((options) {
        if (options.path.endsWith('/Users/AuthenticateByName')) {
          return {
            'AccessToken': 'emby-token',
            'User': {'Id': 'user-1'},
          };
        }
        if (options.path.contains('/System/Info/Public')) {
          return {'Version': '4.8.0'};
        }
        return {'Items': <dynamic>[]};
      }),
    );
    addTearDown(client.dispose);
    final service = NasService(
      kind: NasKind.emby,
      store: store,
      client: client,
    );
    addTearDown(service.dispose);
    final ping = await service.connect(
      baseUrl: 'http://192.168.1.8:8096/',
      username: 'alice',
      password: 'secret',
    );
    expect(ping.ok, isTrue);
    expect(service.isConnected, isTrue);
    expect(service.config.userId, 'user-1');

    final source = MusicSourceService(
      CustomSourceService(),
      nasServices: {NasKind.emby: service},
    );
    addTearDown(source.dispose);
    final result = await source.resolvePlayableUrl(
      MusicItem(
        id: '42',
        name: 'Song',
        singer: 'Artist',
        source: 'emby',
        platform: 'emby',
        songmid: '42',
      ),
      preferredQuality: '320k',
    );
    expect(result, isNotNull);
    expect(result!.platform, 'emby');
    expect(result.url, contains('http://192.168.1.8:8096/Audio/42/stream'));
  });
}
