import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/features/ai/domain/ai_chat.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/presentation/ai_assistant_screen.dart';
import 'package:koyze/features/ai/presentation/ai_provider.dart';
import 'package:koyze/features/ai/presentation/voice_recorder.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('标题和模型名居中', (tester) async {
    await tester.pumpWidget(_app(_FakeRecorder()));
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

  testWidgets('录音不写输入框，而是挂成一段待发送的语音', (tester) async {
    final recorder = _FakeRecorder();
    await tester.pumpWidget(_app(recorder));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.pump();

    expect(recorder.starts, 1);
    // 录音中：图标变成停止，提示语换成计时。
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.textContaining('Recording'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    await tester.pump();

    expect(recorder.stops, 1);
    // 关键点：语音没有被转成文字塞进输入框。
    expect(_inputText(tester), isEmpty);
    expect(find.text('Voice · 5s'), findsOneWidget);
  });

  testWidgets('只有语音、没有文字也能发出去', (tester) async {
    final recorder = _FakeRecorder();
    final chat = _RecordingChat();
    await tester.pumpWidget(
      _app(recorder, [aiChatProvider.overrideWith(() => chat)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();

    expect(chat.sent, hasLength(1));
    expect(chat.sent.single.text, isEmpty);
    expect(chat.sent.single.voice?.seconds, 5);
    // 发完就把待发送的那段清掉。
    expect(find.text('Voice · 5s'), findsNothing);
  });

  testWidgets('语音可以单独撤掉，撤掉之后发送按钮不再可用', (tester) async {
    final recorder = _FakeRecorder();
    final chat = _RecordingChat();
    await tester.pumpWidget(
      _app(recorder, [aiChatProvider.overrideWith(() => chat)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    await tester.pump();
    expect(find.text('Voice · 5s'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump();
    expect(find.text('Voice · 5s'), findsNothing);

    // 按钮这时是禁用的（没有语音也没有文字），点它本来就不该有任何反应。
    await tester.tap(
      find.byIcon(Icons.arrow_upward_rounded),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(chat.sent, isEmpty);
  });

  testWidgets('平台不支持录音时，麦克风根本不出现', (tester) async {
    await tester.pumpWidget(_app(_FakeRecorder(supported: false)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('定时任务的回复也走气泡，并标出来源', (tester) async {
    final container = _container(_FakeRecorder());
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

  testWidgets('失败气泡带上接口原话，而不是只有一句泛泛的提示', (tester) async {
    await tester.pumpWidget(
      _app(_FakeRecorder(), [aiChatProvider.overrideWith(_FailedChat.new)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('The endpoint rejected this request'), findsOneWidget);
    expect(find.textContaining('maximum context length'), findsOneWidget);
  });

  testWidgets('用户气泡会把语音标注出来', (tester) async {
    await tester.pumpWidget(
      _app(_FakeRecorder(), [
        aiChatProvider.overrideWith(
          () => _ChatWithVoice((seconds: 7, text: 'play something calm')),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Voice · 7s'), findsOneWidget);
    expect(find.text('play something calm'), findsOneWidget);
  });
}

String _inputText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

ProviderContainer _container(
  AiVoiceRecorder recorder, [
  List<Override> extra = const [],
]) {
  final container = ProviderContainer(
    overrides: [aiVoiceRecorderProvider.overrideWithValue(recorder), ...extra],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(AiVoiceRecorder recorder, [List<Override> extra = const []]) =>
    UncontrolledProviderScope(
      container: _container(recorder, extra),
      child: const MaterialApp(
        locale: Locale('en'),
        home: AiAssistantScreen(),
      ),
    );

/// 固定返回一条失败回复，用来验气泡的文案。
class _FailedChat extends AiChatNotifier {
  @override
  AiChatState build() => const AiChatState(
    entries: [
      AiChatEntry(
        role: AiChatRole.assistant,
        failure: AiFailureKind.rejected,
        detail: 'maximum context length is 8192 tokens',
      ),
    ],
  );
}

/// 只有一条带语音的用户消息，用来验气泡上的语音标注。
class _ChatWithVoice extends AiChatNotifier {
  _ChatWithVoice(this._entry);

  final ({int seconds, String text}) _entry;

  @override
  AiChatState build() => AiChatState(
    entries: [
      AiChatEntry(
        role: AiChatRole.user,
        text: _entry.text,
        voiceSeconds: _entry.seconds,
      ),
    ],
  );
}

/// 记下 send 收到的东西，不去碰网络和文件。
class _RecordingChat extends AiChatNotifier {
  final List<({String text, AiVoiceClip? voice})> sent = [];

  @override
  AiChatState build() => const AiChatState();

  @override
  Future<void> send(String input, {AiVoiceClip? voice}) async {
    sent.add((text: input, voice: voice));
  }
}

class _FakeRecorder implements AiVoiceRecorder {
  _FakeRecorder({this.supported = true});

  final bool supported;
  bool _recording = false;
  int starts = 0;
  int stops = 0;
  int cancels = 0;

  @override
  bool get isSupported => supported;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> start() async {
    if (!supported) return false;
    starts++;
    _recording = true;
    return true;
  }

  @override
  Future<AiVoiceClip?> stop() async {
    stops++;
    _recording = false;
    return const AiVoiceClip(
      path: '/tmp/koyze-voice-test.wav',
      duration: Duration(seconds: 5),
      format: 'wav',
      bytes: 160000,
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _recording = false;
  }

  @override
  Future<void> dispose() async {}
}
