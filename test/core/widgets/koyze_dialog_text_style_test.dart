import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/koyze_modal.dart';

/// 弹层里的文字必须拿到正常的主题样式。
///
/// `MaterialApp` 在根部装的是 debug 用的 `_errorTextStyle`：红色等宽字，外加
/// 一条 **黄色双下划线**。`showGeneralDialog` 又不会替页面补 `Material`，所以
/// 弹窗内容一旦没自带 `Material`，这套兜底样式就会 merge 到每一行文字上。
/// 之前侧边栏（22c8eb2）和歌词分享卡片导出的 PNG 上出现的黄线都是这个原因。
///
/// 这里量的是「文字最终生效的样式」，而不是某个具体控件——换成任何写法都能
/// 覆盖到，只要样式链断了就会红。
Future<void> _openDialogWithText(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showKoyzeDialog<void>(
            context: context,
            builder: (_) => const Center(
              child: Text('dialog-body', key: ValueKey('dialog-body')),
            ),
          ),
          child: const Text('open-dialog'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-dialog'));
  await tester.pumpAndSettle();
}

TextStyle _effectiveStyle(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('dialog-body'));
  final element = tester.element(finder);
  final own = tester.widget<Text>(finder).style;
  return DefaultTextStyle.of(element).style.merge(own);
}

void main() {
  testWidgets('弹窗裸内容不会继承 debug 的黄色双下划线', (tester) async {
    await _openDialogWithText(tester);
    final style = _effectiveStyle(tester);

    expect(
      style.decoration,
      isNot(TextDecoration.underline),
      reason: 'MaterialApp 的兜底样式带 underline，说明弹窗里没有 Material 祖先',
    );
    expect(
      style.decorationColor,
      isNot(const Color(0xFFFFFF00)),
      reason: '这一项是兜底样式专有的黄色，出现即代表样式链断了',
    );
  });

  testWidgets('弹窗里也不会落到等宽字体', (tester) async {
    await _openDialogWithText(tester);
    final style = _effectiveStyle(tester);

    expect(
      style.fontFamily,
      isNot('monospace'),
      reason: '_errorTextStyle 用等宽字体提示开发者，正常文字不应该继承',
    );
    expect(
      style.fontSize,
      isNot(48.0),
      reason: '48 是兜底字号的标志',
    );
  });
}
