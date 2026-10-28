import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/ai_client.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/domain/ai_playlist_planner.dart';
import 'package:koyze/features/ai/domain/ai_tools.dart';
import 'ai_tool_fakes.dart';

/// 按顺序返回预设响应，并把每次请求体记下来。
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
    final body = bodies[requests.length - 1];
    return ResponseBody.fromString(
      body,
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
  const config = AiConfig(
    baseUrl: 'https://api.test/v1',
    model: 'test-model',
    toolsEnabled: true,
  );

  AiToolbox toolbox() => ToolFakes().toolbox();

  test('feeds tool results back before asking for the playlist', () async {
    final adapter = _SequenceAdapter([
      '{"choices":[{"message":{"role":"assistant","content":"",'
          '"tool_calls":[{"id":"call_1","type":"function","function":'
          '{"name":"search_library","arguments":"{\\"query\\":\\"周杰伦\\"}"}}]}}]}',
      '{"choices":[{"message":{"role":"assistant","content":'
          '"{\\"name\\":\\"晴天合集\\",\\"description\\":\\"\\",\\"songs\\":'
          '[{\\"title\\":\\"晴天\\",\\"artist\\":\\"周杰伦\\",'
          '\\"reason\\":\\"经典\\"}]}"}}]}',
    ]);
    final planner = AiPlaylistPlanner(
      client: AiClient(dio: Dio()..httpClientAdapter = adapter),
    );
    final seen = <String>[];

    final draft = await planner.planWithTools(
      config: config,
      apiKey: 'sk-1',
      request: '来点周杰伦',
      toolbox: toolbox(),
      onToolCall: (call) => seen.add(call.name),
    );

    expect(seen, ['search_library']);
    expect(draft.name, '晴天合集');
    expect(draft.songs.single.title, '晴天');

    expect(adapter.requests, hasLength(2));
    final second = adapter.requests[1]['messages'] as List;
    final assistantTurn = second[second.length - 2] as Map;
    expect(assistantTurn['role'], 'assistant');
    expect((assistantTurn['tool_calls'] as List).single['id'], 'call_1');

    final toolTurn = second.last as Map;
    expect(toolTurn['role'], 'tool');
    expect(toolTurn['tool_call_id'], 'call_1');
    final payload = jsonDecode(toolTurn['content'] as String) as Map;
    expect((payload['songs'] as List).first['title'], '晴天');
  });

  test('stops after the round budget instead of looping forever', () async {
    final endless = jsonEncode({
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'call_x',
                'type': 'function',
                'function': {'name': 'list_playlists', 'arguments': '{}'},
              },
            ],
          },
        },
      ],
    });
    final adapter = _SequenceAdapter(List.filled(3, endless));
    final planner = AiPlaylistPlanner(
      client: AiClient(dio: Dio()..httpClientAdapter = adapter),
    );

    await expectLater(
      planner.planWithTools(
        config: config,
        apiKey: 'sk-1',
        request: '随便',
        toolbox: toolbox(),
        maxRounds: 3,
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.badResponse,
        ),
      ),
    );
    expect(adapter.requests, hasLength(3));
  });
}
