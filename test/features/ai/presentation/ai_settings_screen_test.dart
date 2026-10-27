import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/storage/secure_token_store.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/ai/domain/ai_client.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/domain/ai_config_store.dart';
import 'package:koyze/features/ai/domain/ai_credential_store.dart';
import 'package:koyze/features/ai/presentation/ai_provider.dart';
import 'package:koyze/features/ai/presentation/ai_settings_screen.dart';

void main() {
  late StorageService storage;
  late _MemoryTokenStore tokens;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = StorageService.forTesting(await SharedPreferences.getInstance());
    tokens = _MemoryTokenStore();
  });

  testWidgets('fills the fields from the saved config', (tester) async {
    await storage.setJson(AiConfigStore.storageKey, const AiConfig(
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
    ).toJson());
    tokens.values[originTokenKey(
      aiApiKeyNamespace,
      'https://api.deepseek.com/v1',
    )] = 'sk-stored';

    await tester.pumpWidget(_app(storage, tokens));
    await _open(tester);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList(growable: false);
    expect(fields[0].controller!.text, 'https://api.deepseek.com/v1');
    expect(fields[1].controller!.text, 'deepseek-chat');
    // 已存过密钥时提示语变成「留空即保留」。
    expect(find.text('Saved — leave blank to keep it'), findsOneWidget);
  });

  testWidgets('refuses to save an incomplete config', (tester) async {
    await tester.pumpWidget(_app(storage, tokens));
    await _open(tester);

    await tester.enterText(find.byType(TextField).first, 'api.deepseek.com');
    await tester.enterText(find.byType(TextField).at(1), 'deepseek-chat');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // 页面还在，配置也没写进去。
    expect(find.text('AI settings'), findsOneWidget);
    expect(storage.getJson(AiConfigStore.storageKey), isNull);
  });

  testWidgets('saves the config and the key, then closes', (tester) async {
    await tester.pumpWidget(_app(storage, tokens));
    await _open(tester);

    await tester.enterText(
      find.byType(TextField).first,
      'https://api.deepseek.com',
    );
    await tester.enterText(find.byType(TextField).at(1), 'deepseek-chat');
    await tester.enterText(find.byType(TextField).at(2), 'sk-test');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('AI settings'), findsNothing);
    expect(storage.getJson(AiConfigStore.storageKey), {
      'baseUrl': 'https://api.deepseek.com',
      'model': 'deepseek-chat',
    });
    // 密钥按接口地址隔离，不跟配置一起落盘。
    expect(
      tokens.values[originTokenKey(aiApiKeyNamespace, 'https://api.deepseek.com')],
      equals('sk-test'),
    );
    expect(
      storage.getJson(AiConfigStore.storageKey).toString(),
      isNot(contains('sk-test')),
    );
  });

  testWidgets('a working endpoint reports success without closing', (
    tester,
  ) async {
    await tester.pumpWidget(_app(storage, tokens));
    await _open(tester);

    await tester.enterText(find.byType(TextField).first, 'https://api.test');
    await tester.enterText(find.byType(TextField).at(1), 'm');
    await tester.enterText(find.byType(TextField).at(2), 'sk-test');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('AI settings'), findsOneWidget);
    expect(find.text('Testing…'), findsNothing);
    // 测试连接不该顺手保存。
    expect(storage.getJson(AiConfigStore.storageKey), isNull);
  });

  testWidgets('a rejected key stays on the page', (tester) async {
    await tester.pumpWidget(_app(storage, tokens, status: 401));
    await _open(tester);

    await tester.enterText(find.byType(TextField).first, 'https://api.test');
    await tester.enterText(find.byType(TextField).at(1), 'm');
    await tester.enterText(find.byType(TextField).at(2), 'sk-wrong');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('AI settings'), findsOneWidget);
    expect(find.text('Testing…'), findsNothing);
  });
}

Widget _app(
  StorageService storage,
  _MemoryTokenStore tokens, {
  int status = 200,
}) {
  final container = ProviderContainer(
    overrides: [
      aiConfigStoreProvider.overrideWithValue(
        AiConfigStore(storage: () async => storage),
      ),
      aiCredentialStoreProvider.overrideWithValue(
        AiCredentialStore(tokenStore: tokens),
      ),
      aiClientProvider.overrideWithValue(
        AiClient(dio: Dio()..httpClientAdapter = _StubAdapter(status)),
      ),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: _Host()),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// 用一个能 pop 回去的宿主页面，才能判断设置页有没有关掉。
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const AiSettingsScreen(),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.status);

  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      status >= 400
          ? '{"error":{"message":"nope"}}'
          : '{"choices":[{"message":{"content":"ok"}}]}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryTokenStore implements SecureTokenStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
