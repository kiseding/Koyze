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
    expect(adapter.request!.uri.toString(), 'https://api.test/v1/chat/completions');
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
    final client = AiClient(dio: Dio()..httpClientAdapter = _StubAdapter(200, ''));

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
    expect(await kindOf(503), AiFailureKind.serverError);
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
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.timeout,
        ),
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
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.network,
        ),
      ),
    );
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.status, this.body) : _type = null;

  _StubAdapter.receiveTimeout()
    : status = 0,
      body = '',
      _type = DioExceptionType.receiveTimeout;

  _StubAdapter.connectionError()
    : status = 0,
      body = '',
      _type = DioExceptionType.connectionError;

  final int status;
  final String body;
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
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
