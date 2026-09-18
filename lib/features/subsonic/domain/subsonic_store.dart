import 'dart:convert';

import '../../../core/storage/secure_token_store.dart';
import '../../../core/storage/storage_service.dart';
import 'subsonic_config.dart';

const subsonicPasswordNamespace = 'subsonic_password';
const subsonicConfigPrefsKey = 'subsonic_config';

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

  Future<String?> loadPassword(String baseUrl) async {
    if (baseUrl.trim().isEmpty) return null;
    try {
      return _tokenStore.read(originTokenKey(subsonicPasswordNamespace, baseUrl));
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
    } catch (_) {}
  }

  Future<void> clear() async {
    final config = await loadConfig();
    await deletePassword(config.baseUrl);
    try {
      await (await _storage()).remove(subsonicConfigPrefsKey);
    } catch (_) {}
  }
}
