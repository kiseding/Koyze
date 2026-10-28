import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/ai_agent.dart';
import 'package:koyze/features/ai/domain/ai_client.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/domain/ai_tools.dart';

import 'ai_tool_fakes.dart';

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.bodies);

  final List<String> bodies;
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(Map<String, dynamic>.from(options.data as Map));
    return ResponseBody.fromString(
      bodies[requests.length - 1],
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const config = AiConfig(baseUrl: 'https://api.test/v1', model: 'test-model');

  test('runs the requested tools and reports what it did', () async {
    final adapter = _SequenceAdapter([
      '{"choices":[{"message":{"role":"assistant","content":"",'
          '"tool_calls":[{"id":"call_1","type":"function","function":'
          '{"name":"play_song","arguments":'
          '"{\\"title\\":\\"晴天\\",\\"artist\\":\\"周杰伦\\"}"}}]}}]}',
      '{"choices":[{"message":{"role":"assistant",'
          '"content":"已经在放《晴天》了。"}}]}',
    ]);
    final fakes = ToolFakes();
    final agent = AiAgent(
      client: AiClient(dio: Dio()..httpClientAdapter = adapter),
    );
    final seen = <String>[];

    final reply = await agent.run(
      config: config,
      apiKey: 'sk-1',
      history: const [AiMessage(AiRole.user, '放首晴天')],
      toolbox: fakes.toolbox(),
      onToolCall: (call) => seen.add(call.name),
    );

    expect(seen, ['play_song']);
    expect(reply.text, '已经在放《晴天》了。');
    expect(reply.toolRuns.single.name, AiToolbox.playSong);
    expect(reply.toolRuns.single.category, AiToolCategory.playback);
    expect(reply.toolRuns.single.ok, isTrue);
    expect(fakes.playback.played.single.name, '晴天');

    // 第二轮请求里应该带着工具结果，模型据此收尾。
    final messages = adapter.requests[1]['messages'] as List;
    expect((messages.last as Map)['role'], 'tool');
  });

  test(
    'keeps the tools out of the payload when they are switched off',
    () async {
      final adapter = _SequenceAdapter([
        '{"choices":[{"message":{"role":"assistant","content":"只是聊聊。"}}]}',
      ]);
      final fakes = ToolFakes();
      final agent = AiAgent(
        client: AiClient(dio: Dio()..httpClientAdapter = adapter),
      );

      final reply = await agent.run(
        config: config,
        apiKey: 'sk-1',
        history: const [AiMessage(AiRole.user, '你好')],
        toolbox: fakes.toolbox(),
        useTools: false,
      );

      expect(reply.text, '只是聊聊。');
      expect(reply.toolRuns, isEmpty);
      expect(adapter.requests.single.containsKey('tools'), isFalse);
    },
  );

  test('system prompt states the current playback and the permission', () {
    final fakes = ToolFakes();
    fakes.playback.currentSong = song('1', '晴天', '周杰伦');

    final granted = AiAgent.systemPrompt(fakes.toolbox());
    expect(granted, contains('正在播放《晴天》'));
    expect(granted, contains('已授权你直接执行操作'));

    final readOnly = AiAgent.systemPrompt(fakes.toolbox(allowActions: false));
    expect(readOnly, contains('关闭了执行权限'));
  });
}
