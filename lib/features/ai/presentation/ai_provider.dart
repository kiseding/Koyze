// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';
import '../../search/presentation/search_provider.dart';
import '../domain/ai_client.dart';
import '../domain/ai_config.dart';
import '../domain/ai_config_store.dart';
import '../domain/ai_credential_store.dart';
import '../domain/ai_playlist_planner.dart';

final aiConfigStoreProvider = Provider<AiConfigStore>(
  (ref) => AiConfigStore(),
);

final aiCredentialStoreProvider = Provider<AiCredentialStore>(
  (ref) => AiCredentialStore(),
);

final aiClientProvider = Provider<AiClient>((ref) => AiClient());

final aiPlannerProvider = Provider<AiPlaylistPlanner>((ref) {
  return AiPlaylistPlanner(client: ref.watch(aiClientProvider));
});

final aiMatcherProvider = Provider<AiPlaylistMatcher>((ref) {
  return AiPlaylistMatcher(service: ref.watch(musicSourceServiceProvider));
});

final aiConfigProvider = NotifierProvider<AiConfigNotifier, AiConfig>(
  AiConfigNotifier.new,
);

/// 当前 AI 配置。密钥不在状态里，只存进/取出系统安全存储。
class AiConfigNotifier extends BuildlessNotifier<AiConfig> {
  AiConfigNotifier() : super(AiConfig.empty);

  @override
  AiConfig build() {
    unawaited(_hydrate());
    return super.build();
  }

  Future<void> _hydrate() async {
    final config = await ref.read(aiConfigStoreProvider).load();
    if (!mounted) return;
    publish(config);
  }

  Future<void> save(AiConfig config) async {
    await ref.read(aiConfigStoreProvider).save(config);
    if (!mounted) return;
    publish(config);
  }

  Future<String?> loadKey({String? baseUrl}) {
    final url = baseUrl ?? value.baseUrl;
    return ref.read(aiCredentialStoreProvider).loadKey(url);
  }

  /// 传空串表示清除已保存的密钥。
  Future<void> saveKey(String apiKey, {String? baseUrl}) async {
    final url = baseUrl ?? value.baseUrl;
    final store = ref.read(aiCredentialStoreProvider);
    if (apiKey.trim().isEmpty) {
      await store.deleteKey(url);
      return;
    }
    await store.saveKey(url, apiKey.trim());
  }
}
