import 'dart:convert';

import '../../../core/storage/secure_token_store.dart';
import '../../../core/storage/storage_service.dart';
import '../../nas/domain/nas_client.dart';
import 'subsonic_config.dart';
import '../../../core/logging/app_log.dart';

const subsonicPasswordNamespace = 'subsonic_password';
const subsonicConfigPrefsKey = 'subsonic_config';
const subsonicServersPrefsKey = 'subsonic_servers';
const subsonicQualityPrefsKey = 'subsonic_stream_quality';

class SubsonicStore {
  SubsonicStore({
    StorageLoader? storage,
    SecureTokenStore? tokenStore,
  })  : _storage = storage ?? (() => StorageService.instance),
        _tokenStore = tokenStore ?? FlutterSecureTokenStore();

  final StorageLoader _storage;
  final SecureTokenStore _tokenStore;

  Future<SubsonicConfig> loadConfig() async {
    try {
      final raw = (await _storage()).getString(subsonicConfigPrefsKey);
      if (raw == null || raw.isEmpty) return SubsonicConfig.empty;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return SubsonicConfig.empty;
      return SubsonicConfig.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return SubsonicConfig.empty;
    }
  }

  Future<void> saveConfig(SubsonicConfig config) async {
    await (await _storage()).setString(
      subsonicConfigPrefsKey,
      jsonEncode(config.toJson()),
    );
  }

  /// 同一个 Subsonic 兼容协议下记住的所有服务器。
  Future<List<SubsonicConfig>> loadServers() async {
    try {
      final raw = (await _storage()).getString(subsonicServersPrefsKey);
      if (raw == null || raw.isEmpty) {
        final legacy = await loadConfig();
        return legacy.isConfigured ? [legacy] : const [];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final servers = <SubsonicConfig>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final config = SubsonicConfig.fromJson(
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

  Future<void> saveServers(List<SubsonicConfig> servers) async {
    await (await _storage()).setString(
      subsonicServersPrefsKey,
      jsonEncode([for (final server in servers) server.toJson()]),
    );
  }

  Future<String> loadStreamQuality() async {
    try {
      final raw = (await _storage()).getString(subsonicQualityPrefsKey);
      if (raw == null || raw.isEmpty) return kNasQualityOriginal;
      return raw;
    } catch (_) {
      return kNasQualityOriginal;
    }
  }

  Future<void> saveStreamQuality(String quality) async {
    await (await _storage()).setString(subsonicQualityPrefsKey, quality);
  }

  Future<String?> loadPassword(String baseUrl) async {
    if (baseUrl.trim().isEmpty) return null;
    try {
      return await _tokenStore.read(
        originTokenKey(subsonicPasswordNamespace, baseUrl),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> savePassword(String baseUrl, String password) async {
    await _tokenStore.write(
      originTokenKey(subsonicPasswordNamespace, baseUrl),
      password,
    );
  }

  Future<void> deletePassword(String baseUrl) async {
    if (baseUrl.trim().isEmpty) return;
    try {
      await _tokenStore.delete(
        originTokenKey(subsonicPasswordNamespace, baseUrl),
      );
    } catch (error) {
      AppLog.instance.record('subsonic.credentials', 'deleting Subsonic password for $baseUrl failed: $error', level: AppLogLevel.warning);
    }
  }

  Future<void> clear() async {
    final config = await loadConfig();
    await deletePassword(config.baseUrl);
    try {
      await (await _storage()).remove(subsonicConfigPrefsKey);
    } catch (error) {
      AppLog.instance.record('subsonic.config', 'clearing Subsonic config failed: $error', level: AppLogLevel.warning);
    }
  }
}
