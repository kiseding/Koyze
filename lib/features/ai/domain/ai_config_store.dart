// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import '../../../core/storage/storage_service.dart';
import 'ai_config.dart';

/// AI 配置（地址 + 模型名）的落盘位置。密钥不在这里。
class AiConfigStore {
  AiConfigStore({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance);

  static const String storageKey = 'ai_config';

  final StorageLoader _storage;

  Future<AiConfig> load() async {
    try {
      final json = (await _storage()).getJson(storageKey);
      if (json == null) return AiConfig.empty;
      return AiConfig.fromJson(json);
    } catch (_) {
      return AiConfig.empty;
    }
  }

  Future<void> save(AiConfig config) async {
    await (await _storage()).setJson(storageKey, config.toJson());
  }
}
