import 'dart:async';

import '../../player/domain/music_item.dart';
import 'nas_client.dart';
import 'nas_clients.dart';
import 'nas_config.dart';
import 'nas_kind.dart';
import 'nas_store.dart';
import 'nas_url.dart';

class NasService {
  NasService({
    required NasKind kind,
    NasStore? store,
    NasClient? client,
  })  : kind = kind,
        _store = store ?? NasStore(kind: kind),
        _client = client ?? createNasClient(kind),
        _config = NasConfig.empty(kind);

  final NasKind kind;
  final NasStore _store;
  final NasClient _client;
  final StreamController<int> _revisionController =
      StreamController<int>.broadcast();

  NasConfig _config;
  NasSecrets _secrets = const NasSecrets();
  bool _initialized = false;
  Future<void>? _initFuture;
  int _revision = 0;

  NasConfig get config => _config;
  bool get isConnected =>
      _config.isConfigured &&
      _config.enabled &&
      (_secrets.hasToken || _secrets.hasPassword);
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
      _secrets = await _store.loadSecrets(_config.baseUrl);
    }
    _revisionController.add(++_revision);
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await init();
  }

  Future<NasPingResult> connect({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    await _ensureInit();
    final normalized = validateNasServiceUrl(baseUrl);
    var next = NasConfig(
      kind: kind,
      baseUrl: normalized,
      username: username.trim(),
      userId: _config.userId,
      deviceId: _config.deviceId,
      enabled: true,
    );
    if (kind != NasKind.plex && next.username.isEmpty) {
      throw ArgumentError.value(username, 'username', '用户名不能为空');
    }
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', '密码不能为空');
    }
    final tokenOnly = kind == NasKind.plex && next.username.isEmpty;
    final incoming = NasSecrets(
      password: tokenOnly ? null : password,
      token: tokenOnly ? password : null,
    );
    final ping = await _client.connect(next, incoming);
    if (!ping.ok) return ping;
    next = next.copyWith(userId: ping.userId ?? next.userId);
    final previousUrl = _config.baseUrl;
    _config = next;
    _secrets = NasSecrets(
      password: tokenOnly ? null : password,
      token: ping.token ?? incoming.token,
    );
    await _store.saveConfig(next);
    await _store.saveSecrets(normalized, _secrets);
    if (previousUrl.isNotEmpty && previousUrl != normalized) {
      await _store.deleteSecrets(previousUrl);
    }
    _revisionController.add(++_revision);
    return ping;
  }

  Future<void> disconnect() async {
    await _ensureInit();
    final previousUrl = _config.baseUrl;
    _config = NasConfig.empty(kind);
    _secrets = const NasSecrets();
    await _store.saveConfig(_config);
    await _store.deleteSecrets(previousUrl);
    _revisionController.add(++_revision);
  }

  Future<List<NasPlaylistInfo>> getPlaylists() async {
    final session = await _session();
    if (session == null) return const [];
    return _client.getPlaylists(session.config, session.secrets);
  }

  Future<List<MusicItem>> getPlaylistSongs(String playlistId) async {
    final session = await _session();
    if (session == null) return const [];
    return _client.getPlaylistSongs(
      session.config,
      session.secrets,
      playlistId,
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
      session.secrets,
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
      session.secrets,
      music,
      quality: quality,
    );
  }

  Future<String?> getLyric(MusicItem music) async {
    final session = await _session();
    if (session == null) return null;
    return _client.getLyrics(session.config, session.secrets, music);
  }

  Future<NasSession?> _session() async {
    await _ensureInit();
    if (!_config.enabled ||
        !_config.isConfigured ||
        (!_secrets.hasToken && !_secrets.hasPassword)) {
      return null;
    }
    return NasSession(config: _config, secrets: _secrets);
  }

  void dispose() {
    _revisionController.close();
    _client.dispose();
  }
}
