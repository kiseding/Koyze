import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/features/ai/presentation/ai_assistant_screen.dart';
import 'package:koyze/features/ai/presentation/ai_provider.dart';
import 'package:koyze/features/ai/presentation/voice_input.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('标题和模型名居中', (tester) async {
    final voice = _FakeVoice();
    await tester.pumpWidget(_app(voice));
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.centerTitle, isTrue);
    // 标题列在 AppBar 的 title 位置，且自身也是居中的。
    final column = tester.widget<Column>(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(Column),
      ).first,
    );
    expect(column.crossAxisAlignment, CrossAxisAlignment.center);
    expect(find.text('AI assistant'), findsOneWidget);
  });

  testWidgets('点麦克风开始听写，识别结果写进输入框', (tester) async {
    final voice = _FakeVoice();
    await tester.pumpWidget(_app(voice));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    expect(voice.starts, 1);
    // 聆听中：图标变成停止，提示语也换了。
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);

    voice.emit('play 晴天');
    await tester.pump();
    expect(_inputText(tester), 'play 晴天');

    // 中间的识别结果覆盖上一版，不会越拼越长。
    voice.emit('play 晴天 周杰伦');
    await tester.pump();
    expect(_inputText(tester), 'play 晴天 周杰伦');

    // 最终结果回来后自动收麦。
    voice.emit('play 晴天 周杰伦', finalResult: true);
    await tester.pumpAndSettle();
    expect(_inputText(tester), 'play 晴天 周杰伦');
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
  });

  testWidgets('再点一次就停下，已有文字保留在前面', (tester) async {
    final voice = _FakeVoice();
    await tester.pumpWidget(_app(voice));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '把这首');
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();

    voice.emit('加进收藏');
    await tester.pump();
    expect(_inputText(tester), '把这首 加进收藏');

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pumpAndSettle();
    expect(voice.stops, 1);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
  });

  testWidgets('平台不支持语音时，麦克风根本不出现', (tester) async {
    final voice = _FakeVoice(supported: false);
    await tester.pumpWidget(_app(voice));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('定时任务的回复也走气泡，并标出来源', (tester) async {
    final voice = _FakeVoice();
    final container = _container(voice);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          home: AiAssistantScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    container
        .read(aiChatProvider.notifier)
        .recordScheduled(title: 'Morning picks', text: 'Picked 5 songs for you');
    await tester.pumpAndSettle();

    expect(find.text('Picked 5 songs for you'), findsOneWidget);
    expect(find.text('Scheduled · Morning picks'), findsOneWidget);

    // 助手消息靠左，是气泡（最近的那层 Align 就是它的对齐方式）。
    final align = tester.widget<Align>(
      find
          .ancestor(
            of: find.text('Picked 5 songs for you'),
            matching: find.byType(Align),
          )
          .first,
    );
    expect(align.alignment, Alignment.centerLeft);
  });
}

String _inputText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

ProviderContainer _container(AiVoiceInput voice) {
  final container = ProviderContainer(
    overrides: [aiVoiceInputProvider.overrideWithValue(voice)],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(AiVoiceInput voice) => UncontrolledProviderScope(
  container: _container(voice),
  child: const MaterialApp(locale: Locale('en'), home: AiAssistantScreen()),
);

class _FakeVoice implements AiVoiceInput {
  _FakeVoice({this.supported = true});

  final bool supported;
  VoiceResultCallback? _onResult;
  bool _listening = false;
  int starts = 0;
  int stops = 0;

  @override
  bool get isSupported => supported;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> start(
    VoiceResultCallback onResult, {
    String? localeId,
    VoidCallback? onEnd,
  }) async {
    if (!supported) return false;
    starts++;
    _onResult = onResult;
    _listening = true;
    return true;
  }

  @override
  Future<void> stop() async {
    stops++;
    _listening = false;
  }

  @override
  Future<void> cancel() async => _listening = false;

  void emit(String words, {bool finalResult = false}) {
    if (finalResult) _listening = false;
    _onResult?.call(words, finalResult);
  }
}
