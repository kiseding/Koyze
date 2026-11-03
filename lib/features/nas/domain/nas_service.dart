import 'dart:async';

import '../../../core/network/artwork_auth_registry.dart';
import '../../player/domain/music_item.dart';
import 'nas_client.dart';
import 'nas_clients.dart';
import 'nas_config.dart';
import 'nas_kind.dart';
import 'nas_store.dart';
import 'nas_url.dart';
import 'plex_client.dart';
import 'webdav_client.dart';

class NasService {
  NasService({required NasKind kind, NasStore? store, NasClient? client})
    : kind = kind,
      _store = store ?? NasStore(kind: kind),
      _client = client ?? createNasClient(kind),
      _config = NasConfig.empty(kind);

  final NasKind kind;
  final NasStore _store;
  final NasClient _client;
  final StreamController<int> _revisionController =
      StreamController<int>.broadcast();

  NasConfig _config;
  List<NasConfig> _servers = const [];
  String _streamQuality = kNasQualityOriginal;
  NasSecrets _secrets = const NasSecrets();
  bool _initialized = false;
  Future<void>? _initFuture;
  int _revision = 0;

  NasConfig get config => _config;

  /// 这个协议下记住的所有服务器，最后一个是最近用的。
  List<NasConfig> get servers => _servers;

  /// 串流码率档位：original / 320k / 192k / 128k。
  String get streamQuality => _streamQuality;

  Future<void> setStreamQuality(String quality) async {
    await _ensureInit();
    if (_streamQuality == quality) return;
    _streamQuality = quality;
    await _store.saveStreamQuality(quality);
    _revisionController.add(++_revision);
  }

  /// Plex 的「用账号登录」要先跟 plex.tv 换 token，这一步发生在 connect 之前，
  /// 所以把底层客户端借出去，让设置页能拿到同一个 clientId。
  PlexNasClient? get plexClient {
    final client = _client;
    return client is PlexNasClient ? client : null;
  }
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
    _servers = await _store.loadServers();
    _streamQuality = await _store.loadStreamQuality();
    _config = await _store.loadConfig();
    if (_config.baseUrl.isEmpty) {
      // 配置丢了但列表还在（换版本/清缓存），退回到最近一台。
      for (final server in _servers.reversed) {
        if (server.isConfigured) {
          _config = server;
          break;
        }
      }
    }
    if (_config.baseUrl.isNotEmpty) {
      _secrets = await _store.loadSecrets(_config.baseUrl);
    }
    _registerArtworkAuth();
    _revisionController.add(++_revision);
  }

  /// WebDAV 的封面图要带 Authorization；把当前连接的头登记到全局表，
  /// 让图片加载器能取到。
  void _registerArtworkAuth() {
    if (_config.baseUrl.isEmpty) return;
    registerArtworkAuth(
      _config.baseUrl,
      _client.artworkHeaders(_config, _secrets),
    );
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await init();
  }

  Future<NasPingResult> connect({
    required String baseUrl,
    required String username,
    required String password,
    String? rootPath,
    NasAuthMethod? authMethod,
    String? deviceId,
  }) async {
    await _ensureInit();
    final normalized = validateNasServiceUrl(baseUrl);
    final method = kind == NasKind.webdav
        ? (authMethod ?? _config.authMethod)
        : NasAuthMethod.basic;
    var next = NasConfig(
      kind: kind,
      baseUrl: normalized,
      username: username.trim(),
      userId: _config.userId,
      deviceId: deviceId ?? _config.deviceId,
      rootPath: kind == NasKind.webdav
          ? normalizeNasRootPath(rootPath ?? _config.rootPath)
          : '/',
      authMethod: method,
      enabled: true,
    );
    final plexTokenOnly = kind == NasKind.plex && next.username.isEmpty;
    final webDavBearer =
        kind == NasKind.webdav && method == NasAuthMethod.bearer;
    if (webDavBearer) {
      if (password.isEmpty) {
        throw ArgumentError.value(password, 'password', '请输入 Bearer token');
      }
    } else {
      if (kind != NasKind.plex && next.username.isEmpty) {
        throw ArgumentError.value(username, 'username', '用户名不能为空');
      }
      if (password.isEmpty) {
        throw ArgumentError.value(password, 'password', '密码不能为空');
      }
    }
    final incoming = NasSecrets(
      password: plexTokenOnly || webDavBearer ? null : password,
      token: plexTokenOnly || webDavBearer ? password : null,
    );
    final ping = await _client.connect(next, incoming);
    if (!ping.ok) return ping;
    next = next.copyWith(userId: ping.userId ?? next.userId);
    final previousUrl = _config.baseUrl;
    _config = next;
    _secrets = NasSecrets(
      password: incoming.hasPassword ? password : null,
      token: incoming.hasToken ? (ping.token ?? incoming.token) : null,
    );
    await _store.saveConfig(next);
    await _store.saveSecrets(normalized, _secrets);
    _servers = _upsertServer(_servers, next);
    await _store.saveServers(_servers);
    if (previousUrl.isNotEmpty && previousUrl != normalized) {
      // 换到另一台服务器不等于不要旧的那台：凭据按 origin 存，
      // 留着才能随时切回去。只有显式 disconnect / removeServer 才删。
      clearArtworkAuth(previousUrl);
    }
    _registerArtworkAuth();
    _revisionController.add(++_revision);
    return ping;
  }

  /// 切到另一台已经连过的服务器。凭据按 origin 存在钥匙串里，
  /// 所以这里只要换 config + 重新读一次密码就行。
  Future<bool> switchTo(String baseUrl) async {
    await _ensureInit();
    final target = _serverWith(baseUrl);
    if (target == null) return false;
    if (target.baseUrl == _config.baseUrl) return true;
    final previousUrl = _config.baseUrl;
    _secrets = await _store.loadSecrets(target.baseUrl);
    _config = target;
    await _store.saveConfig(target);
    if (previousUrl.isNotEmpty) clearArtworkAuth(previousUrl);
    _registerArtworkAuth();
    _revisionController.add(++_revision);
    return true;
  }

  Future<void> removeServer(String baseUrl) async {
    await _ensureInit();
    if (baseUrl.trim().isEmpty) return;
    final remaining = [
      for (final server in _servers)
        if (server.baseUrl != baseUrl) server,
    ];
    _servers = remaining;
    await _store.saveServers(remaining);
    await _store.deleteSecrets(baseUrl);
    clearArtworkAuth(baseUrl);
    if (_config.baseUrl == baseUrl) {
      if (remaining.isEmpty) {
        _config = NasConfig.empty(kind);
        _secrets = const NasSecrets();
        await _store.saveConfig(_config);
      } else {
        _config = remaining.last;
        _secrets = await _store.loadSecrets(_config.baseUrl);
        await _store.saveConfig(_config);
        _registerArtworkAuth();
      }
    }
    _revisionController.add(++_revision);
  }

  NasConfig? _serverWith(String baseUrl) {
    for (final server in _servers) {
      if (server.baseUrl == baseUrl) return server;
    }
    return null;
  }

  List<NasConfig> _upsertServer(List<NasConfig> list, NasConfig config) {
    final next = <NasConfig>[];
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

  Future<void> disconnect() async {
    await _ensureInit();
    final previousUrl = _config.baseUrl;
    _config = NasConfig.empty(kind);
    _secrets = const NasSecrets();
    // 断开 = 忘掉这台，连同它在服务器列表里的条目。
    _servers = [
      for (final server in _servers)
        if (server.baseUrl != previousUrl) server,
    ];
    await _store.saveConfig(_config);
    await _store.saveServers(_servers);
    await _store.deleteSecrets(previousUrl);
    clearArtworkAuth(previousUrl);
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

  Future<List<MusicItem>> getLibrarySongs({int limit = kNasLibraryLimit}) async {
    final session = await _session();
    if (session == null) return const [];
    return _client.getLibrarySongs(
      session.config,
      session.secrets,
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
      session.secrets,
      query,
      page: page,
      limit: limit,
    );
  }

  Future<NasPlayUrlResult?> getPlayUrlResult(
    MusicItem music, {
    String quality = '320k',
  }) async {
    final session = await _session();
    if (session == null) return null;
    final id = music.songmid?.isNotEmpty == true ? music.songmid! : music.id;
    if (id.isEmpty) return null;
    return _client.streamResult(
      session.config,
      session.secrets,
      music,
      quality: _effectiveQuality(quality),
    );
  }

  Future<String?> getPlayUrl(MusicItem music, {String quality = '320k'}) async {
    final result = await getPlayUrlResult(music, quality: quality);
    return result?.url;
  }

  /// NAS 有自己的档位设置，选了具体档位就照它来；没设过才跟随全局音质。
  String _effectiveQuality(String requested) =>
      _streamQuality.isEmpty ? requested : _streamQuality;

  /// 目录选择器用：列出 WebDAV 服务下的子目录。
  Future<List<WebDavDirectory>> listDirectories(String path) async {
    final session = await _session();
    if (session == null) return const [];
    final client = _client;
    if (client is WebDavNasClient) {
      return client.listDirectories(session.config, session.secrets, path);
    }
    return const [];
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
