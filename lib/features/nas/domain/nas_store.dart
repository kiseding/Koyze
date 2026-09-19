import 'dart:convert';

import '../../../core/storage/secure_token_store.dart';
import '../../../core/storage/storage_service.dart';
import 'nas_config.dart';
import 'nas_kind.dart';

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
      } catch (_) {}
    }
    if (secrets.hasToken) {
      await _tokenStore.write(tokenKey, secrets.token!);
    } else {
      try {
        await _tokenStore.delete(tokenKey);
      } catch (_) {}
    }
  }

  Future<void> deleteSecrets(String baseUrl) async {
    if (baseUrl.trim().isEmpty) return;
    try {
      await _tokenStore.delete(originTokenKey(_passwordNs, baseUrl));
    } catch (_) {}
    try {
      await _tokenStore.delete(originTokenKey(_tokenNs, baseUrl));
    } catch (_) {}
  }

  Future<void> clear() async {
    final config = await loadConfig();
    await deleteSecrets(config.baseUrl);
    try {
      await (await _storage()).remove(_configKey);
    } catch (_) {}
  }
}
