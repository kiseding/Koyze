import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/ai_client.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';

void main() {
  const config = AiConfig(baseUrl: 'https://api.test/v1', model: 'test-model');

  test('posts the OpenAI shape and returns the message content', () async {
    final adapter = _StubAdapter(
      200,
      '{"choices":[{"message":{"role":"assistant","content":"你好"}}]}',
    );
    final client = AiClient(dio: Dio()..httpClientAdapter = adapter);

    final content = await client.complete(
      config: config,
      apiKey: ' sk-1 ',
      messages: const [AiMessage(AiRole.user, 'hi')],
    );

    expect(content, equals('你好'));
    expect(
      adapter.request!.uri.toString(),
      'https://api.test/v1/chat/completions',
    );
    expect(adapter.request!.headers['Authorization'], 'Bearer sk-1');
    final body = adapter.request!.data as Map<String, dynamic>;
    expect(body['model'], 'test-model');
    expect(body['stream'], isFalse);
    expect(body['messages'], [
      {'role': 'user', 'content': 'hi'},
    ]);
  });

  test('joins content that the backend split into parts', () async {
    final client = AiClient(
      dio: Dio()
        ..httpClientAdapter = _StubAdapter(
          200,
          '{"choices":[{"message":{"content":[{"type":"text","text":"a"},'
          '{"type":"text","text":"b"}]}}]}',
        ),
    );

    expect(
      await client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      equals('ab'),
    );
  });

  test('refuses to run without a config or a key', () async {
    final client = AiClient(
      dio: Dio()..httpClientAdapter = _StubAdapter(200, ''),
    );

    await expectLater(
      client.complete(
        config: const AiConfig(model: 'm'),
        apiKey: 'k',
        messages: const [],
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.notConfigured,
        ),
      ),
    );
    await expectLater(
      client.complete(config: config, apiKey: '  ', messages: const []),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.unauthorized,
        ),
      ),
    );
  });

  test('maps status codes onto failure kinds', () async {
    Future<AiFailureKind> kindOf(int status, [String body = '{}']) async {
      final client = AiClient(
        dio: Dio()..httpClientAdapter = _StubAdapter(status, body),
      );
      try {
        await client.complete(
          config: config,
          apiKey: 'k',
          messages: const [AiMessage(AiRole.user, 'hi')],
        );
      } on AiException catch (error) {
        return error.kind;
      }
      fail('no exception for $status');
    }

    expect(await kindOf(401), AiFailureKind.unauthorized);
    expect(await kindOf(403), AiFailureKind.unauthorized);
    expect(await kindOf(404), AiFailureKind.notFound);
    expect(await kindOf(429), AiFailureKind.rateLimited);
    expect(await kindOf(400), AiFailureKind.badResponse);
    expect(await kindOf(500), AiFailureKind.serverError);
    expect(await kindOf(502), AiFailureKind.gatewayTimeout);
    expect(await kindOf(503), AiFailureKind.gatewayTimeout);
    expect(await kindOf(504), AiFailureKind.gatewayTimeout);
  });

  test('surfaces the backend error message for 5xx', () async {
    final client = AiClient(
      dio: Dio()
        ..httpClientAdapter = _StubAdapter(
          500,
          '{"error":{"message":"model overloaded"}}',
        ),
    );

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.detail,
          'detail',
          'model overloaded',
        ),
      ),
    );
  });

  test('a 400 about context length becomes its own kind', () async {
    final client = AiClient(
      dio: Dio()
        ..httpClientAdapter = _StubAdapter(
          400,
          '{"error":{"message":"maximum context length is 8192 tokens. '
          'However, your messages resulted in 9000 tokens."}}',
        ),
    );

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.contextTooLong,
        ),
      ),
    );
  });

  test('a 400 about tools becomes its own kind', () async {
    final client = AiClient(
      dio: Dio()
        ..httpClientAdapter = _StubAdapter(
          400,
          '{"error":{"message":"tools is not supported for this model"}}',
        ),
    );

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.toolsUnsupported,
        ),
      ),
    );
  });


  test('纯文字消息仍然发字符串，老网关不会被内容数组卡住', () async {
    final adapter = _StubAdapter(
      200,
      '{"choices":[{"message":{"content":"ok"}}]}',
    );
    final client = AiClient(dio: Dio()..httpClientAdapter = adapter);

    await client.complete(
      config: config,
      apiKey: 'k',
      messages: const [AiMessage(AiRole.user, 'hi')],
    );

    final body = adapter.request!.data as Map<String, dynamic>;
    expect((body['messages'] as List).single['content'], 'hi');
  });



  test('any other 4xx keeps the backend wording so it can be acted on', () async {
    final client = AiClient(
      dio: Dio()
        ..httpClientAdapter = _StubAdapter(
          422,
          '{"error":{"message":"invalid request: model is required"}}',
        ),
    );

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiFailureKind.rejected)
            .having((e) => e.detail, 'detail', 'invalid request: model is required'),
      ),
    );
  });

  test('网关超时的 HTML 页面只留标题，不把整页贴进气泡', () async {
    final client = AiClient(
      dio: Dio()
        ..httpClientAdapter = _StubAdapter(
          504,
          '<!DOCTYPE html><html><head><title>504 Gateway Timeout</title>'
          '</head><body><center><h1>504 Gateway Time-out</h1></center>'
          '<hr><center>nginx</center></body></html>',
          contentType: Headers.textPlainContentType,
        ),
    );

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiFailureKind.gatewayTimeout)
            .having((e) => e.detail, 'detail', '504 Gateway Timeout'),
      ),
    );
  });

  test('5xx 会自动重试一次，第二次成功就当没事发生', () async {
    final adapter = _SequenceAdapter([
      (status: 502, body: '{"error":{"message":"upstream error"}}'),
      (
        status: 200,
        body: '{"choices":[{"message":{"role":"assistant","content":"好了"}}]}',
      ),
    ]);
    final client = AiClient(dio: Dio()..httpClientAdapter = adapter);

    final content = await client.complete(
      config: config,
      apiKey: 'k',
      messages: const [AiMessage(AiRole.user, 'hi')],
    );

    expect(content, '好了');
    expect(adapter.calls, 2);
  });

  test('两次都 5xx 才报错，不会一直重试', () async {
    final adapter = _SequenceAdapter([
      (status: 502, body: '{"error":{"message":"upstream error"}}'),
      (status: 502, body: '{"error":{"message":"upstream error"}}'),
    ]);
    final client = AiClient(dio: Dio()..httpClientAdapter = adapter);

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.gatewayTimeout,
        ),
      ),
    );
    expect(adapter.calls, 2);
  });

  test('4xx 不重试，同样的无效请求只发一次', () async {
    final adapter = _SequenceAdapter([
      (status: 400, body: '{"error":{"message":"invalid request"}}'),
      (
        status: 200,
        body: '{"choices":[{"message":{"content":"不该走到这里"}}]}',
      ),
    ]);
    final client = AiClient(dio: Dio()..httpClientAdapter = adapter);

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(isA<AiException>()),
    );
    expect(adapter.calls, 1);
  });

  test('an answer with no choices is an empty response, not a crash', () async {
    final client = AiClient(
      dio: Dio()..httpClientAdapter = _StubAdapter(200, '{"choices":[]}'),
    );

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.emptyResponse,
        ),
      ),
    );
  });

  test('a timeout is reported as its own kind', () async {
    final client = AiClient(
      dio: Dio()..httpClientAdapter = _StubAdapter.receiveTimeout(),
    );

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(
        isA<AiException>().having((e) => e.kind, 'kind', AiFailureKind.timeout),
      ),
    );
  });

  test('a transport failure is reported as a network error', () async {
    final client = AiClient(
      dio: Dio()..httpClientAdapter = _StubAdapter.connectionError(),
    );

    await expectLater(
      client.complete(
        config: config,
        apiKey: 'k',
        messages: const [AiMessage(AiRole.user, 'hi')],
      ),
      throwsA(
        isA<AiException>().having((e) => e.kind, 'kind', AiFailureKind.network),
      ),
    );
  });
  test('parses tool calls out of the assistant message', () async {
    final adapter = _StubAdapter(
      200,
      '{"choices":[{"message":{"role":"assistant","content":null,'
      '"tool_calls":[{"id":"call_1","type":"function","function":'
      '{"name":"search_library","arguments":"{\\"query\\":\\"周杰伦\\"}"}}]}}]}',
    );
    final client = AiClient(dio: Dio()..httpClientAdapter = adapter);

    final completion = await client.completeDetailed(
      config: config,
      apiKey: 'sk-1',
      messages: const [AiMessage(AiRole.user, 'hi')],
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'search_library',
            'parameters': {'type': 'object'},
          },
        },
      ],
    );

    expect(completion.content, isEmpty);
    expect(completion.hasToolCalls, isTrue);
    expect(completion.toolCalls.single.id, 'call_1');
    expect(completion.toolCalls.single.name, 'search_library');
    expect(completion.toolCalls.single.arguments, {'query': '周杰伦'});

    final body = adapter.request!.data as Map<String, dynamic>;
    expect(body['tool_choice'], 'auto');
    expect(body['tools'], hasLength(1));
  });

  test('omits tools from the payload when none are offered', () async {
    final adapter = _StubAdapter(
      200,
      '{"choices":[{"message":{"content":"ok"}}]}',
    );
    final client = AiClient(dio: Dio()..httpClientAdapter = adapter);

    await client.complete(
      config: config,
      apiKey: 'sk-1',
      messages: const [AiMessage(AiRole.user, 'hi')],
    );

    final body = adapter.request!.data as Map<String, dynamic>;
    expect(body.containsKey('tools'), isFalse);
    expect(body.containsKey('tool_choice'), isFalse);
  });

  test('tool results serialise with role, content and call id', () {
    expect(const AiMessage.tool('{"ok":true}', toolCallId: 'call_1').toJson(), {
      'role': 'tool',
      'content': '{"ok":true}',
      'tool_call_id': 'call_1',
    });
    expect(
      const AiMessage(
        AiRole.assistant,
        '',
        toolCalls: [
          AiToolCall(
            id: 'call_1',
            name: 'search_library',
            arguments: {'query': 'x'},
          ),
        ],
      ).toJson(),
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {
              'name': 'search_library',
              'arguments': '{"query":"x"}',
            },
          },
        ],
      },
    );
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(
    this.status,
    this.body, {
    this.contentType = Headers.jsonContentType,
  }) : _type = null;

  _StubAdapter.receiveTimeout()
    : status = 0,
      body = '',
      contentType = Headers.jsonContentType,
      _type = DioExceptionType.receiveTimeout;

  _StubAdapter.connectionError()
    : status = 0,
      body = '',
      contentType = Headers.jsonContentType,
      _type = DioExceptionType.connectionError;

  final int status;
  final String body;
  final String contentType;
  final DioExceptionType? _type;

  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    final type = _type;
    if (type != null) {
      throw DioException(requestOptions: options, type: type);
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 按顺序返回多次响应，用来验证「失败后重试一次」。
class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.replies);

  final List<({int status, String body})> replies;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final reply = replies[calls.clamp(0, replies.length - 1)];
    calls++;
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
