// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'voice_recorder.dart';

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
    recommendations: ProviderAiRecommendationPort(ref),
    settings: ProviderAiSettingsPort(ref),
    equalizer: ProviderAiEqualizerPort(ref),
    stats: ProviderAiStatsPort(ref),
    lyrics: ProviderAiLyricPort(ref),
    charts: ProviderAiChartPort(ref),
    schedules: ProviderAiSchedulePort(ref),
    local: ProviderAiLocalPort(ref),
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

  /// 发出去之前的硬上限。一分钟 16 kHz 单声道 wav 约 1.9 MB，base64 之后
  /// 2.6 MB；超过 8 MB 就别让网关拿 413 回我们了。
  static const int _maxVoiceBytes = 8 * 1024 * 1024;

  /// [voice] 非空表示这条消息带一段录音，和 [input] 一起发出去。
  /// 只发文字时 [input] 不能为空；带语音时文字可以留空。
  Future<void> send(String input, {AiVoiceClip? voice}) async {
    final text = input.trim();
    if ((text.isEmpty && voice == null) || value.busy) return;

    final entries = [
      ...value.entries,
      AiChatEntry(
        role: AiChatRole.user,
        text: text,
        voiceSeconds: voice?.seconds,
      ),
    ];
    _emit(entries, busy: true);

    final config = ref.read(aiConfigProvider);
    if (!config.isConfigured) {
      await discardVoiceClip(voice);
      _fail(entries, AiFailureKind.notConfigured);
      return;
    }
    final key = await ref.read(aiConfigProvider.notifier).loadKey();
    if (key == null || key.isEmpty) {
      await discardVoiceClip(voice);
      _fail(entries, AiFailureKind.unauthorized);
      return;
    }

    // 录音只在这一轮发一次：进了历史就变成纯文字摘要，否则每次追问都要
    // 把几 MB 的 base64 重发一遍。
    final AiVoiceAttachment? attachment;
    if (voice != null) {
      if (voice.bytes > _maxVoiceBytes) {
        await discardVoiceClip(voice);
        _fail(entries, AiFailureKind.audioTooLarge);
        return;
      }
      try {
        attachment = AiVoiceAttachment(
          base64Data: base64Encode(await File(voice.path).readAsBytes()),
          format: voice.format,
        );
      } catch (_) {
        await discardVoiceClip(voice);
        _fail(entries, AiFailureKind.audioTooLarge);
        return;
      }
    } else {
      attachment = null;
    }

    final userMessage = AiMessage(AiRole.user, text, voice: attachment);
    final historyLine = text.isEmpty
        ? '（语音 ${voice?.seconds ?? 0} 秒）'
        : text;
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
        ..add(AiMessage(AiRole.user, historyLine))
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
      _fail(entries, error.kind, error.detail);
    } catch (_) {
      if (!mounted) return;
      _fail(entries, AiFailureKind.network);
    } finally {
      await discardVoiceClip(voice);
    }
  }

  void clear() {
    _history.clear();
    if (!mounted) return;
    publish(const AiChatState());
  }

  /// 定时任务跑完把结果丢进对话里，用户下次打开助手能看到它做过什么。
  ///
  /// 不进 [_history]：这属于「通知」，不是用户问的话，回传给模型只会干扰
  /// 下一轮对话。busy 保持原样，免得把正在进行的请求标成空闲。
  void recordScheduled({
    required String title,
    String text = '',
    List<AiToolRun> toolRuns = const <AiToolRun>[],
    AiFailureKind? failure,
    String? detail,
  }) {
    if (!mounted) return;
    final entry = AiChatEntry(
      role: AiChatRole.assistant,
      text: text,
      toolRuns: toolRuns,
      failure: failure,
      detail: detail,
      scheduleTitle: title,
    );
    publish(
      AiChatState(
        entries: [...value.entries, entry],
        busy: value.busy,
        activeTool: value.activeTool,
      ),
    );
  }

  void _fail(List<AiChatEntry> entries, AiFailureKind kind, [String? detail]) {
    if (!mounted) return;
    final note = (detail ?? '').trim();
    _emit([
      ...entries,
      AiChatEntry(
        role: AiChatRole.assistant,
        failure: kind,
        detail: note.isEmpty ? null : note,
      ),
    ]);
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
