import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';

void main() {
  group('endpoint', () {
    test('appends the chat path to a bare host', () {
      expect(
        const AiConfig(baseUrl: 'https://api.deepseek.com').endpoint,
        equals('https://api.deepseek.com/chat/completions'),
      );
    });

    test('keeps a base path such as /v1', () {
      expect(
        const AiConfig(baseUrl: 'https://api.openai.com/v1').endpoint,
        equals('https://api.openai.com/v1/chat/completions'),
      );
    });

    test('does not append twice when already complete', () {
      expect(
        const AiConfig(
          baseUrl: 'https://x.test/v1/chat/completions',
        ).endpoint,
        equals('https://x.test/v1/chat/completions'),
      );
    });

    test('tolerates trailing slashes and whitespace', () {
      expect(
        const AiConfig(baseUrl: '  https://x.test/v1//  ').endpoint,
        equals('https://x.test/v1/chat/completions'),
      );
    });

    test('is empty when nothing is configured', () {
      expect(const AiConfig().endpoint, isEmpty);
      expect(const AiConfig(baseUrl: '   ').endpoint, isEmpty);
    });
  });

  group('validate', () {
    test('reports a missing address before anything else', () {
      expect(
        const AiConfig(model: 'gpt').validate(),
        equals(AiConfigProblem.missingBaseUrl),
      );
    });

    test('rejects a non-http scheme and a hostless address', () {
      expect(
        const AiConfig(
          baseUrl: 'ftp://x.test',
          model: 'm',
        ).validate(),
        equals(AiConfigProblem.invalidBaseUrl),
      );
      expect(
        const AiConfig(baseUrl: 'api.deepseek.com', model: 'm').validate(),
        equals(AiConfigProblem.invalidBaseUrl),
      );
    });

    test('accepts plain http for a self-hosted gateway', () {
      expect(
        const AiConfig(baseUrl: 'http://192.168.1.5:3000', model: 'm').validate(),
        isNull,
      );
    });

    test('asks for a model name last', () {
      expect(
        const AiConfig(baseUrl: 'https://x.test').validate(),
        equals(AiConfigProblem.missingModel),
      );
      expect(
        const AiConfig(baseUrl: 'https://x.test', model: ' ').validate(),
        equals(AiConfigProblem.missingModel),
      );
    });
  });

  test('isConfigured needs both halves', () {
    expect(const AiConfig(baseUrl: 'https://x.test').isConfigured, isFalse);
    expect(const AiConfig(model: 'm').isConfigured, isFalse);
    expect(
      const AiConfig(baseUrl: 'https://x.test', model: 'm').isConfigured,
      isTrue,
    );
  });

  test('toJson trims what it stores', () {
    const config = AiConfig(baseUrl: ' https://x.test/v1/ ', model: ' m ');
    expect(config.toJson(), {
      'baseUrl': 'https://x.test/v1',
      'model': 'm',
    });
    expect(AiConfig.fromJson(config.toJson()), equals(config.copyWith(
      baseUrl: 'https://x.test/v1',
      model: 'm',
    )));
  });

  test('an empty JSON object reads as unconfigured', () {
    final config = AiConfig.fromJson(const {});
    expect(config.baseUrl, isEmpty);
    expect(config.model, isEmpty);
    expect(config.isConfigured, isFalse);
  });

  test('messages serialise with the role name the API expects', () {
    expect(const AiMessage(AiRole.system, 'hi').toJson(), {
      'role': 'system',
      'content': 'hi',
    });
  });
}
