// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import '../../../core/storage/secure_token_store.dart';
import 'ai_config.dart';

const String aiApiKeyNamespace = 'ai_api_key';

/// AI 密钥的读写。
///
/// 按接口地址做命名空间隔离：换一家服务商时旧密钥不会被顺带发出去。地址本身
/// 不敏感，存在 SharedPreferences 里；密钥只进系统安全存储。
class AiCredentialStore {
  AiCredentialStore({SecureTokenStore? tokenStore})
    : _tokenStore = tokenStore ?? FlutterSecureTokenStore();

  final SecureTokenStore _tokenStore;

  Future<String?> loadKey(String baseUrl) async {
    if (AiConfig.normalizeBaseUrl(baseUrl).isEmpty) return null;
    try {
      final value = await _tokenStore.read(
        originTokenKey(aiApiKeyNamespace, baseUrl),
      );
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveKey(String baseUrl, String key) async {
    await _tokenStore.write(originTokenKey(aiApiKeyNamespace, baseUrl), key);
  }

  Future<void> deleteKey(String baseUrl) async {
    if (AiConfig.normalizeBaseUrl(baseUrl).isEmpty) return;
    try {
      await _tokenStore.delete(originTokenKey(aiApiKeyNamespace, baseUrl));
    } catch (_) {
      // 删不掉也不该让设置页报错。
    }
  }
}
