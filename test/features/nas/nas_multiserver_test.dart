import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/secure_token_store.dart';
import 'package:koyze/features/nas/domain/mediabrowser_client.dart';
import 'package:koyze/features/nas/domain/plex_client.dart';
import 'package:koyze/features/nas/domain/nas_client.dart';
import 'package:koyze/features/nas/domain/nas_config.dart';
import 'package:koyze/features/nas/domain/nas_kind.dart';
import 'package:koyze/features/nas/domain/nas_service.dart';
import 'package:koyze/features/nas/domain/nas_store.dart';
import 'package:koyze/features/nas/domain/webdav_client.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/subsonic/domain/subsonic_client.dart';
import 'package:koyze/features/subsonic/domain/subsonic_config.dart';

const _pingResponse = '''<?xml version="1.0" encoding="utf-8"?>
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
</d:multistatus>''';

/// 所有 PROPFIND 都回同一份 multistatus：这里只关心服务层怎么存服务器，
/// 不关心目录解析。
Dio _pingDio() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 207,
            data: _pingResponse,
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

class _MemoryNasStore extends NasStore {
  _MemoryNasStore({required this.tokens}) : super(kind: NasKind.webdav);

  final _MemoryTokenStore tokens;
  NasConfig? config;
  List<NasConfig> servers = const [];
  final Map<String, NasSecrets> secrets = {};
  String quality = kNasQualityOriginal;

  @override
  Future<NasConfig> loadConfig() async => config ?? NasConfig.empty(kind);

  @override
  Future<void> saveConfig(NasConfig next) async => config = next;

  @override
  Future<List<NasConfig>> loadServers() async => servers;

  @override
  Future<void> saveServers(List<NasConfig> next) async =>
      servers = List<NasConfig>.of(next);

  @override
  Future<NasSecrets> loadSecrets(String baseUrl) async =>
      secrets[baseUrl] ?? const NasSecrets();

  @override
  Future<void> saveSecrets(String baseUrl, NasSecrets next) async {
    secrets[baseUrl] = next;
    if (next.hasPassword) await tokens.write('pwd:$baseUrl', next.password!);
  }

  @override
  Future<void> deleteSecrets(String baseUrl) async {
    secrets.remove(baseUrl);
    await tokens.delete('pwd:$baseUrl');
  }

  @override
  Future<String> loadStreamQuality() async => quality;

  @override
  Future<void> saveStreamQuality(String next) async => quality = next;
}

NasService _service(_MemoryNasStore store) {
  return NasService(
    kind: NasKind.webdav,
    store: store,
    client: WebDavNasClient(dio: _pingDio()),
  );
}

MusicItem _song() => MusicItem(
  id: 'p1',
  name: 'Song',
  singer: 'Artist',
  source: 'plex',
  platform: 'plex',
  songmid: 'p1',
);

void main() {
  group('多服务器', () {
    test('连第二台不会把第一台的配置和凭据冲掉', () async {
      final store = _MemoryNasStore(tokens: _MemoryTokenStore());
      final service = _service(store);
      addTearDown(service.dispose);

      final first = await service.connect(
        baseUrl: 'http://home.local:5005',
        username: 'alice',
        password: 'home-pass',
        rootPath: '/music',
      );
      final second = await service.connect(
        baseUrl: 'http://office.local:5005',
        username: 'bob',
        password: 'office-pass',
        rootPath: '/music',
      );

      expect(first.ok, isTrue);
      expect(second.ok, isTrue);
      expect(service.servers, hasLength(2));
      expect(service.config.baseUrl, 'http://office.local:5005');
      expect(store.secrets['http://home.local:5005']!.password, 'home-pass');
      expect(store.secrets['http://office.local:5005']!.password, 'office-pass');
    });

    test('重启后服务器列表还在，当前指向最后连的那台', () async {
      final store = _MemoryNasStore(tokens: _MemoryTokenStore());
      final service = _service(store);
      await service.connect(
        baseUrl: 'http://home.local:5005',
        username: 'alice',
        password: 'home-pass',
        rootPath: '/music',
      );
      await service.connect(
        baseUrl: 'http://office.local:5005',
        username: 'bob',
        password: 'office-pass',
        rootPath: '/music',
      );
      service.dispose();

      final reopened = _service(store);
      addTearDown(reopened.dispose);
      await reopened.init();

      expect(reopened.servers, hasLength(2));
      expect(reopened.config.baseUrl, 'http://office.local:5005');
      expect(reopened.isConnected, isTrue);
    });

    test('switchTo 换回第一台时不用重新输密码', () async {
      final store = _MemoryNasStore(tokens: _MemoryTokenStore());
      final service = _service(store);
      addTearDown(service.dispose);

      await service.connect(
        baseUrl: 'http://home.local:5005',
        username: 'alice',
        password: 'home-pass',
        rootPath: '/music',
      );
      await service.connect(
        baseUrl: 'http://office.local:5005',
        username: 'bob',
        password: 'office-pass',
        rootPath: '/music',
      );

      final switched = await service.switchTo('http://home.local:5005');

      expect(switched, isTrue);
      expect(service.config.baseUrl, 'http://home.local:5005');
      expect(service.config.username, 'alice');
      expect(service.isConnected, isTrue);
      expect(store.config!.baseUrl, 'http://home.local:5005');
    });

    test('删掉当前服务器会退回剩下的那台', () async {
      final store = _MemoryNasStore(tokens: _MemoryTokenStore());
      final service = _service(store);
      addTearDown(service.dispose);

      await service.connect(
        baseUrl: 'http://home.local:5005',
        username: 'alice',
        password: 'home-pass',
        rootPath: '/music',
      );
      await service.connect(
        baseUrl: 'http://office.local:5005',
        username: 'bob',
        password: 'office-pass',
        rootPath: '/music',
      );

      await service.removeServer('http://office.local:5005');

      expect(service.servers, hasLength(1));
      expect(service.config.baseUrl, 'http://home.local:5005');
      expect(service.isConnected, isTrue);
      expect(store.secrets.containsKey('http://office.local:5005'), isFalse);
    });

    test('删掉最后一台就回到未配置状态', () async {
      final store = _MemoryNasStore(tokens: _MemoryTokenStore());
      final service = _service(store);
      addTearDown(service.dispose);

      await service.connect(
        baseUrl: 'http://home.local:5005',
        username: 'alice',
        password: 'home-pass',
        rootPath: '/music',
      );
      await service.removeServer('http://home.local:5005');

      expect(service.servers, isEmpty);
      expect(service.config.baseUrl, isEmpty);
      expect(service.isConnected, isFalse);
    });
  });

  group('码率档位', () {
    test('只把有损档位换算成上限', () {
      expect(nasBitrateCapKbps(kNasQualityOriginal), isNull);
      expect(nasBitrateCapKbps('hires'), isNull);
      expect(nasBitrateCapKbps('flac'), isNull);
      expect(nasBitrateCapKbps('320k'), 320);
      expect(nasBitrateCapKbps('192k'), 192);
      expect(nasBitrateCapKbps('128k'), 128);
    });

    test('Subsonic 限码率时要求转成 mp3，原始档位要 raw', () {
      final client = SubsonicClient();
      addTearDown(client.dispose);
      const config = SubsonicConfig(
        baseUrl: 'http://nav.local:4533',
        username: 'alice',
      );

      final capped = client.streamUrl(
        config,
        'secret',
        'song-1',
        quality: '128k',
      );
      expect(capped, contains('maxBitRate=128'));
      expect(capped, contains('format=mp3'));

      final original = client.streamUrl(
        config,
        'secret',
        'song-1',
        quality: kNasQualityOriginal,
      );
      expect(original, contains('format=raw'));
      expect(original, isNot(contains('maxBitRate')));
    });

    test('Emby / Jellyfin 限码率时让服务端转码', () {
      final client = EmbyNasClient();
      addTearDown(client.dispose);
      const config = NasConfig(
        kind: NasKind.emby,
        baseUrl: 'http://emby.local:8096',
        username: 'alice',
      );

      final capped = client.streamUrl(
        config,
        const NasSecrets(token: 'tok'),
        _song(),
        quality: '192k',
      );
      expect(capped, contains('static=false'));
      expect(capped, contains('MaxStreamingBitrate=192000'));

      final original = client.streamUrl(
        config,
        const NasSecrets(token: 'tok'),
        _song(),
        quality: kNasQualityOriginal,
      );
      expect(original, contains('static=true'));
      expect(original, isNot(contains('MaxStreamingBitrate')));
    });

    test('Plex 限码率时走转码接口并带上 maxAudioBitrate', () {
      final client = PlexNasClient();
      addTearDown(client.dispose);
      const config = NasConfig(
        kind: NasKind.plex,
        baseUrl: 'http://plex.local:32400',
        username: '',
      );

      final capped = client.streamUrl(
        config,
        const NasSecrets(token: 'tok'),
        _song(),
        quality: '128k',
      );
      expect(capped, contains('/music/:/transcode/universal/start'));
      expect(capped, contains('maxAudioBitrate=128'));
      expect(capped, contains('directPlay=0'));
    });

    test('服务会记住档位，重启后仍然生效', () async {
      final store = _MemoryNasStore(tokens: _MemoryTokenStore());
      final service = _service(store);
      await service.init();
      await service.setStreamQuality('192k');
      expect(store.quality, '192k');
      service.dispose();

      final reopened = _service(store);
      addTearDown(reopened.dispose);
      await reopened.init();
      expect(reopened.streamQuality, '192k');
    });
  });
}
