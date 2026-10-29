import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/features/ai/domain/ai_chat.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/presentation/ai_assistant_screen.dart';
import 'package:koyze/features/ai/presentation/ai_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('标题和模型名居中', (tester) async {
    await tester.pumpWidget(_app());
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

  testWidgets('定时任务的回复也走气泡，并标出来源', (tester) async {
    final container = _container();
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
      _app([aiChatProvider.overrideWith(_FailedChat.new)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('The endpoint rejected this request'), findsOneWidget);
    expect(find.textContaining('maximum context length'), findsOneWidget);
  });
}

ProviderContainer _container([List<Override> extra = const []]) {
  final container = ProviderContainer(overrides: extra);
  addTearDown(container.dispose);
  return container;
}

Widget _app([List<Override> extra = const []]) => UncontrolledProviderScope(
  container: _container(extra),
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
