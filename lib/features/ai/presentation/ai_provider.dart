// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';
import '../../search/presentation/search_provider.dart';
import '../domain/ai_agent.dart';
import '../domain/ai_chat.dart';
import '../domain/ai_client.dart';
import '../domain/ai_config.dart';
import '../domain/ai_config_store.dart';
import '../domain/ai_credential_store.dart';
import '../domain/ai_tools.dart';
import 'ai_ports.dart';

final aiConfigStoreProvider = Provider<AiConfigStore>((ref) => AiConfigStore());

final aiCredentialStoreProvider = Provider<AiCredentialStore>(
  (ref) => AiCredentialStore(),
);

final aiClientProvider = Provider<AiClient>((ref) => AiClient());

final aiAgentProvider = Provider<AiAgent>((ref) {
  return AiAgent(client: ref.watch(aiClientProvider));
});

/// 交给模型的全部操作。每个端口都直连服务层，模型不经过任何界面。
final aiToolboxProvider = Provider<AiToolbox>((ref) {
  final config = ref.watch(aiConfigProvider);
  return AiToolbox(
    allowActions: config.allowActions,
    playback: ProviderAiPlaybackPort(ref),
    playlists: ProviderAiPlaylistPort(ref),
    downloads: ProviderAiDownloadPort(ref),
    sources: ProviderAiSourcePort(ref),
    settings: ProviderAiSettingsPort(ref),
    search: (query, limit) =>
        ref.read(musicSourceServiceProvider).search(query, limit: limit),
  );
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

/// 助手对话状态。历史只留在内存里，退出应用即清空。
final aiChatProvider = NotifierProvider<AiChatNotifier, AiChatState>(
  AiChatNotifier.new,
);

class AiChatNotifier extends BuildlessNotifier<AiChatState> {
  AiChatNotifier() : super(const AiChatState());

  /// 回传给模型的多轮上下文；和界面上的 [AiChatState.entries] 分开存，
  /// 这样「清空显示」不会把工具调用配对关系弄坏。
  final List<AiMessage> _history = [];

  static const int _maxHistoryMessages = 24;

  Future<void> send(String input) async {
    final text = input.trim();
    if (text.isEmpty || value.busy) return;

    final entries = [
      ...value.entries,
      AiChatEntry(role: AiChatRole.user, text: text),
    ];
    _emit(entries, busy: true);

    final config = ref.read(aiConfigProvider);
    if (!config.isConfigured) {
      _fail(entries, AiFailureKind.notConfigured);
      return;
    }
    final key = await ref.read(aiConfigProvider.notifier).loadKey();
    if (key == null || key.isEmpty) {
      _fail(entries, AiFailureKind.unauthorized);
      return;
    }

    final userMessage = AiMessage(AiRole.user, text);
    try {
      final reply = await ref
          .read(aiAgentProvider)
          .run(
            config: config,
            apiKey: key,
            history: [..._history, userMessage],
            toolbox: ref.read(aiToolboxProvider),
            useTools: config.toolsEnabled,
            onToolCall: (call) {
              if (!mounted) return;
              _emit(
                entries,
                busy: true,
                activeTool: ref
                    .read(aiToolboxProvider)
                    .toolNamed(call.name)
                    ?.category,
              );
            },
          );
      if (!mounted) return;
      _history
        ..add(userMessage)
        ..add(AiMessage(AiRole.assistant, reply.text));
      if (_history.length > _maxHistoryMessages) {
        _history.removeRange(0, _history.length - _maxHistoryMessages);
      }
      _emit([
        ...entries,
        AiChatEntry(
          role: AiChatRole.assistant,
          text: reply.text,
          toolRuns: reply.toolRuns,
        ),
      ]);
    } on AiException catch (error) {
      if (!mounted) return;
      _fail(entries, error.kind);
    } catch (_) {
      if (!mounted) return;
      _fail(entries, AiFailureKind.network);
    }
  }

  void clear() {
    _history.clear();
    if (!mounted) return;
    publish(const AiChatState());
  }

  void _fail(List<AiChatEntry> entries, AiFailureKind kind) {
    if (!mounted) return;
    _emit([...entries, AiChatEntry(role: AiChatRole.assistant, failure: kind)]);
  }

  void _emit(
    List<AiChatEntry> entries, {
    bool busy = false,
    AiToolCategory? activeTool,
  }) {
    if (!mounted) return;
    publish(AiChatState(entries: entries, busy: busy, activeTool: activeTool));
  }
}
