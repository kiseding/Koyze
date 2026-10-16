import 'dart:async';

import '../../player/domain/music_item.dart';
import 'subsonic_client.dart';
import 'subsonic_config.dart';
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
  String? _password;
  bool _initialized = false;
  Future<void>? _initFuture;
  int _revision = 0;

  SubsonicConfig get config => _config;
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
    _config = await _store.loadConfig();
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
    final previousUrl = _config.baseUrl;
    _config = next;
    _password = password;
    await _store.saveConfig(next);
    await _store.savePassword(normalized, password);
    if (previousUrl.isNotEmpty && previousUrl != normalized) {
      await _store.deletePassword(previousUrl);
    }
    _revisionController.add(++_revision);
    return ping;
  }

  Future<void> disconnect() async {
    await _ensureInit();
    final previousUrl = _config.baseUrl;
    _config = SubsonicConfig.empty;
    _password = null;
    await _store.saveConfig(_config);
    await _store.deletePassword(previousUrl);
    _revisionController.add(++_revision);
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

  Future<List<MusicItem>> getLibrarySongs({int limit = 500}) async {
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
      quality: quality,
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
