import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/auto_text_input.dart';

/// `requestTextInput` 的契约只有两条：首帧之后把焦点给到节点，并且不去
/// 碰 widget 树（后者是那个 `_dependents.isEmpty` 红屏的根因，靠签名里
/// 没有 BuildContext 来保证）。
void main() {
  testWidgets('首帧后把焦点交给节点', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextField(focusNode: focus);
            },
          ),
        ),
      ),
    );

    expect(focus.hasFocus, isFalse);
    requestTextInput(focus);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(focus.hasFocus, isTrue);
  });

  testWidgets('节点尚未挂载时不抛异常，挂载后补上焦点', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);

    // 先请求，再挂树：FocusNode 会记住这次请求（_requestFocusWhenReparented）。
    requestTextInput(focus);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(focusNode: focus)),
      ),
    );
    await tester.pump();
    // 再等一轮，把重试那次也跑完，否则测试结束时还留着 pending timer。
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('canRequest 返回 false 时不抢焦点', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TextField(focusNode: focus))),
    );

    requestTextInput(focus, canRequest: () => false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(focus.hasFocus, isFalse);
  });
}
