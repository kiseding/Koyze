import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/ai_client.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/presentation/ai_provider.dart';
import 'package:koyze/features/ai/presentation/voice_recorder.dart';

import '../domain/ai_tool_fakes.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('koyze-voice-');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('录音被读成 base64 发出去，发完就把临时文件删掉', () async {
    final file = File('${tempDir.path}/clip.wav');
    await file.writeAsBytes(List<int>.filled(2048, 7));
    final adapter = _StubAdapter();
    final container = _container(adapter);
    addTearDown(container.dispose);

    await container
        .read(aiChatProvider.notifier)
        .send('', voice: _clip(file.path));

    final messages = _chatMessages(adapter);
    expect(messages, hasLength(1));
    final content = messages.single['content'] as List;
    expect(content.single['type'], 'input_audio');
    expect(
      (content.single['input_audio'] as Map)['data'],
      base64Encode(List<int>.filled(2048, 7)),
    );
    expect(
      (content.single['input_audio'] as Map)['format'],
      'wav',
    );

    // 临时文件不该留在缓存目录里。
    expect(await file.exists(), isFalse);
  });

  test('语音只发一次：下一轮追问的上下文里只有一句时长摘要', () async {
    final file = File('${tempDir.path}/clip.wav');
    await file.writeAsBytes(List<int>.filled(1024, 3));
    final adapter = _StubAdapter();
    final container = _container(adapter);
    addTearDown(container.dispose);
    final chat = container.read(aiChatProvider.notifier);

    await chat.send('', voice: _clip(file.path));
    await chat.send('再来一首');

    final messages = _chatMessages(adapter);
    // 第一轮 1 条 user，第二轮 1 user + 1 assistant + 1 user = 3 条。
    expect(messages, hasLength(3));
    expect(messages[0]['content'], '（语音 5 秒）');
    expect(messages[1]['role'], 'assistant');
    expect(messages[2]['content'], '再来一首');
    // 音频没有进第二轮报文。
    expect(jsonEncode(messages), isNot(contains('input_audio')));
  });

  test('文件读不到时按「录音太大」失败，而不是卡在发送中', () async {
    final adapter = _StubAdapter();
    final container = _container(adapter);
    addTearDown(container.dispose);

    await container
        .read(aiChatProvider.notifier)
        .send('', voice: _clip('${tempDir.path}/missing.wav'));

    final state = container.read(aiChatProvider);
    expect(state.busy, isFalse);
    expect(state.entries.last.failure, AiFailureKind.audioTooLarge);
    expect(adapter.calls, 0);
  });
}

AiVoiceClip _clip(String path) => AiVoiceClip(
  path: path,
  duration: const Duration(seconds: 5),
  format: 'wav',
  bytes: 2048,
);

List _messages(_StubAdapter adapter) {
  final body = adapter.request!.data as Map<String, dynamic>;
  return body['messages'] as List;
}

/// 去掉 system prompt，只看真正的对话轮次。
List _chatMessages(_StubAdapter adapter) =>
    _messages(adapter).where((m) => (m as Map)['role'] != 'system').toList();

ProviderContainer _container(_StubAdapter adapter) => ProviderContainer(
  overrides: [
    aiConfigProvider.overrideWith(_ConfiguredConfig.new),
    aiClientProvider.overrideWithValue(
      AiClient(dio: Dio()..httpClientAdapter = adapter),
    ),
    // 工具关掉了不会真的调用，但 system prompt 需要它念一句当前状态。
    aiToolboxProvider.overrideWithValue(ToolFakes().toolbox()),
  ],
);

/// 已配置好、并且不带工具（避免为了跑通一次对话去装配整个服务层）。
class _ConfiguredConfig extends AiConfigNotifier {
  @override
  AiConfig build() => const AiConfig(
    baseUrl: 'https://api.test/v1',
    model: 'test-model',
    toolsEnabled: false,
  );

  @override
  Future<String?> loadKey({String? baseUrl}) async => 'test-key';
}

class _StubAdapter implements HttpClientAdapter {
  RequestOptions? request;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    calls++;
    return ResponseBody.fromString(
      '{"choices":[{"message":{"role":"assistant","content":"ok"}}]}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
