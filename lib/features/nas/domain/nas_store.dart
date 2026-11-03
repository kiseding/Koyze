import 'dart:convert';

import '../../../core/storage/secure_token_store.dart';
import '../../../core/storage/storage_service.dart';
import 'nas_client.dart';
import 'nas_config.dart';
import 'nas_kind.dart';
import '../../../core/logging/app_log.dart';

class NasStore {
  NasStore({
    required NasKind kind,
    StorageLoader? storage,
    SecureTokenStore? tokenStore,
  })  : kind = kind,
        _storage = storage ?? (() => StorageService.instance),
        _tokenStore = tokenStore ?? FlutterSecureTokenStore();

  final NasKind kind;
  final StorageLoader _storage;
  final SecureTokenStore _tokenStore;

  String get _configKey => '${kind.id}_config';
  String get _serversKey => '${kind.id}_servers';
  String get _qualityKey => '${kind.id}_stream_quality';
  String get _passwordNs => '${kind.id}_password';
  String get _tokenNs => '${kind.id}_token';

  Future<NasConfig> loadConfig() async {
    try {
      final raw = (await _storage()).getString(_configKey);
      if (raw == null || raw.isEmpty) return NasConfig.empty(kind);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return NasConfig.empty(kind);
      return NasConfig.fromJson(kind, Map<String, dynamic>.from(decoded));
    } catch (_) {
      return NasConfig.empty(kind);
    }
  }

  Future<void> saveConfig(NasConfig config) async {
    await (await _storage()).setString(_configKey, jsonEncode(config.toJson()));
  }

  /// 同一个协议下可能有不止一台服务器（家里一台、公司一台）。
  /// 列表存在普通存储里，凭据还是按 origin 分别进钥匙串。
  Future<List<NasConfig>> loadServers() async {
    try {
      final raw = (await _storage()).getString(_serversKey);
      if (raw == null || raw.isEmpty) {
        // 老版本只存了单台，读出来当成唯一的服务器。
        final legacy = await loadConfig();
        return legacy.isConfigured ? [legacy] : const [];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final servers = <NasConfig>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final config = NasConfig.fromJson(
          kind,
          Map<String, dynamic>.from(item),
        );
        if (config.baseUrl.isEmpty) continue;
        servers.add(config);
      }
      return servers;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveServers(List<NasConfig> servers) async {
    await (await _storage()).setString(
      _serversKey,
      jsonEncode([for (final server in servers) server.toJson()]),
    );
  }

  /// 串流码率档位。默认 original：不动原文件，行为和老版本一致。
  Future<String> loadStreamQuality() async {
    try {
      final raw = (await _storage()).getString(_qualityKey);
      if (raw == null || raw.isEmpty) return kNasQualityOriginal;
      return raw;
    } catch (_) {
      return kNasQualityOriginal;
    }
  }

  Future<void> saveStreamQuality(String quality) async {
    await (await _storage()).setString(_qualityKey, quality);
  }

  Future<NasSecrets> loadSecrets(String baseUrl) async {
    if (baseUrl.trim().isEmpty) return const NasSecrets();
    try {
      final password = await _tokenStore.read(
        originTokenKey(_passwordNs, baseUrl),
      );
      final token = await _tokenStore.read(originTokenKey(_tokenNs, baseUrl));
      return NasSecrets(password: password, token: token);
    } catch (_) {
      return const NasSecrets();
    }
  }

  Future<void> saveSecrets(String baseUrl, NasSecrets secrets) async {
    final passwordKey = originTokenKey(_passwordNs, baseUrl);
    final tokenKey = originTokenKey(_tokenNs, baseUrl);
    if (secrets.hasPassword) {
      await _tokenStore.write(passwordKey, secrets.password!);
    } else {
      try {
        await _tokenStore.delete(passwordKey);
      } catch (error) {
        AppLog.instance.record('nas.credentials', 'deleting unused NAS password failed: $error', level: AppLogLevel.warning);
      }
    }
    if (secrets.hasToken) {
      await _tokenStore.write(tokenKey, secrets.token!);
    } else {
      try {
        await _tokenStore.delete(tokenKey);
      } catch (error) {
        AppLog.instance.record('nas.credentials', 'deleting unused NAS token failed: $error', level: AppLogLevel.warning);
      }
    }
  }

  Future<void> deleteSecrets(String baseUrl) async {
    if (baseUrl.trim().isEmpty) return;
    try {
      await _tokenStore.delete(originTokenKey(_passwordNs, baseUrl));
    } catch (error) {
      AppLog.instance.record('nas.credentials', 'deleting NAS password for $baseUrl failed: $error', level: AppLogLevel.warning);
    }
    try {
      await _tokenStore.delete(originTokenKey(_tokenNs, baseUrl));
    } catch (error) {
      AppLog.instance.record('nas.credentials', 'deleting NAS token for $baseUrl failed: $error', level: AppLogLevel.warning);
    }
  }

  Future<void> clear() async {
    final config = await loadConfig();
    await deleteSecrets(config.baseUrl);
    try {
      await (await _storage()).remove(_configKey);
    } catch (error) {
      AppLog.instance.record('nas.config', 'clearing NAS config failed: $error', level: AppLogLevel.warning);
    }
  }
}
