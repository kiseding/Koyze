import 'dart:async';

import '../../player/domain/music_item.dart';
import 'subsonic_client.dart';
import 'subsonic_config.dart';
import '../../nas/domain/nas_client.dart';
import 'subsonic_store.dart';
import 'subsonic_url.dart';

const subsonicSourceId = 'subsonic';
const subsonicLibraryPlaylistId = 'subsonic';

class SubsonicService {
  SubsonicService({
    SubsonicStore? store,
    SubsonicClient? client,
  })  : _store = store ?? SubsonicStore(),
        _client = client ?? SubsonicClient();

  final SubsonicStore _store;
  final SubsonicClient _client;
  final StreamController<int> _revisionController =
      StreamController<int>.broadcast();

  SubsonicConfig _config = SubsonicConfig.empty;
  List<SubsonicConfig> _servers = const [];
  String _streamQuality = kNasQualityOriginal;
  String? _password;
  bool _initialized = false;
  Future<void>? _initFuture;
  int _revision = 0;

  SubsonicConfig get config => _config;

  /// 记住的所有兼容服务器，最后一个是最近用的。
  List<SubsonicConfig> get servers => _servers;

  String get streamQuality => _streamQuality;

  Future<void> setStreamQuality(String quality) async {
    await _ensureInit();
    if (_streamQuality == quality) return;
    _streamQuality = quality;
    await _store.saveStreamQuality(quality);
    _revisionController.add(++_revision);
  }
  bool get isConnected =>
      _config.isConfigured &&
      _config.enabled &&
      (_password?.isNotEmpty ?? false);
  Stream<int> get revisions => _revisionController.stream;
  int get revision => _revision;

  Future<void> init() {
    return _initFuture ??= _load().whenComplete(() {
      _initialized = true;
    });
  }

  Future<void> _load() async {
    _servers = await _store.loadServers();
    _streamQuality = await _store.loadStreamQuality();
    _config = await _store.loadConfig();
    if (_config.baseUrl.isEmpty) {
      for (final server in _servers.reversed) {
        if (server.isConfigured) {
          _config = server;
          break;
        }
      }
    }
    if (_config.baseUrl.isNotEmpty) {
      _password = await _store.loadPassword(_config.baseUrl);
    }
    _revisionController.add(++_revision);
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await init();
  }

  Future<SubsonicPingResult> connect({
    required String baseUrl,
    required String username,
    required String password,
    bool legacyAuth = false,
  }) async {
    await _ensureInit();
    final normalized = validateSubsonicServiceUrl(baseUrl);
    final next = SubsonicConfig(
      baseUrl: normalized,
      username: username.trim(),
      legacyAuth: legacyAuth,
      enabled: true,
    );
    if (next.username.isEmpty) {
      throw ArgumentError.value(username, 'username', '用户名不能为空');
    }
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', '密码不能为空');
    }
    final ping = await _client.ping(next, password);
    if (!ping.ok) {
      return ping;
    }
    _config = next;
    _password = password;
    await _store.saveConfig(next);
    await _store.savePassword(normalized, password);
    _servers = _upsertServer(_servers, next);
    await _store.saveServers(_servers);
    // 旧的密码留着，切回去时不用重新输。
    _revisionController.add(++_revision);
    return ping;
  }

  Future<void> disconnect() async {
    await _ensureInit();
    final previousUrl = _config.baseUrl;
    _config = SubsonicConfig.empty;
    _password = null;
    _servers = [
      for (final server in _servers)
        if (server.baseUrl != previousUrl) server,
    ];
    await _store.saveConfig(_config);
    await _store.saveServers(_servers);
    await _store.deletePassword(previousUrl);
    _revisionController.add(++_revision);
  }

  Future<bool> switchTo(String baseUrl) async {
    await _ensureInit();
    SubsonicConfig? target;
    for (final server in _servers) {
      if (server.baseUrl == baseUrl) {
        target = server;
        break;
      }
    }
    if (target == null) return false;
    if (target.baseUrl == _config.baseUrl) return true;
    _password = await _store.loadPassword(target.baseUrl);
    _config = target;
    await _store.saveConfig(target);
    _revisionController.add(++_revision);
    return true;
  }

  Future<void> removeServer(String baseUrl) async {
    await _ensureInit();
    if (baseUrl.trim().isEmpty) return;
    _servers = [
      for (final server in _servers)
        if (server.baseUrl != baseUrl) server,
    ];
    await _store.saveServers(_servers);
    await _store.deletePassword(baseUrl);
    if (_config.baseUrl == baseUrl) {
      if (_servers.isEmpty) {
        _config = SubsonicConfig.empty;
        _password = null;
        await _store.saveConfig(_config);
      } else {
        _config = _servers.last;
        _password = await _store.loadPassword(_config.baseUrl);
        await _store.saveConfig(_config);
      }
    }
    _revisionController.add(++_revision);
  }

  List<SubsonicConfig> _upsertServer(
    List<SubsonicConfig> list,
    SubsonicConfig config,
  ) {
    final next = <SubsonicConfig>[];
    var replaced = false;
    for (final server in list) {
      if (server.baseUrl == config.baseUrl) {
        next.add(config);
        replaced = true;
      } else {
        next.add(server);
      }
    }
    if (!replaced) next.add(config);
    return next;
  }

  Future<void> setEnabled(bool enabled) async {
    await _ensureInit();
    if (!_config.isConfigured) return;
    _config = _config.copyWith(enabled: enabled);
    await _store.saveConfig(_config);
    _revisionController.add(++_revision);
  }

  Future<List<SubsonicPlaylistInfo>> getPlaylists() async {
    final session = await _session();
    if (session == null) return const [];
    return _client.getPlaylists(session.config, session.password);
  }

  Future<List<MusicItem>> getPlaylistSongs(String playlistId) async {
    final session = await _session();
    if (session == null) return const [];
    return _client.getPlaylistSongs(
      session.config,
      session.password,
      playlistId,
    );
  }

  Future<List<MusicItem>> getLibrarySongs({
    int limit = kNasLibraryLimit,
  }) async {
    final session = await _session();
    if (session == null) return const [];
    return _client.getLibrarySongs(
      session.config,
      session.password,
      limit: limit,
    );
  }

  Future<List<MusicItem>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final session = await _session();
    if (session == null) return const [];
    return _client.search(
      session.config,
      session.password,
      query,
      page: page,
      limit: limit,
    );
  }

  Future<String?> getPlayUrl(MusicItem music, {String quality = '320k'}) async {
    final session = await _session();
    if (session == null) return null;
    final id = music.songmid?.isNotEmpty == true ? music.songmid! : music.id;
    if (id.isEmpty) return null;
    return _client.streamUrl(
      session.config,
      session.password,
      id,
      quality: _streamQuality.isEmpty ? quality : _streamQuality,
    );
  }

  Future<String?> getLyric(MusicItem music) async {
    final session = await _session();
    if (session == null) return null;
    return _client.getLyrics(session.config, session.password, music);
  }

  Future<({SubsonicConfig config, String password})?> _session() async {
    await _ensureInit();
    final password = _password;
    if (!_config.enabled ||
        !_config.isConfigured ||
        password == null ||
        password.isEmpty) {
      return null;
    }
    return (config: _config, password: password);
  }

  void dispose() {
    _revisionController.close();
    _client.dispose();
  }
}
