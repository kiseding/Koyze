import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/fx_switch.dart';

void main() {
  Future<Switch> pumpSwitch(
    WidgetTester tester, {
    required bool value,
    ValueChanged<bool>? onChanged,
    Color? accent,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: FxSwitch(value: value, onChanged: onChanged, accent: accent),
          ),
        ),
      ),
    );
    return tester.widget<Switch>(find.byType(Switch));
  }

  testWidgets('用的是平台开关本身，不再是自绘胶囊', (tester) async {
    await pumpSwitch(tester, value: true, onChanged: (_) {});
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('强调色与 tap 目标跟「翻译行」那颗保持一致', (tester) async {
    const accent = Color(0xFFFF3B30);
    final control = await pumpSwitch(
      tester,
      value: true,
      onChanged: (_) {},
      accent: accent,
    );
    expect(control.activeThumbColor, accent);
    expect(control.materialTapTargetSize, MaterialTapTargetSize.shrinkWrap);
  });

  testWidgets('不传强调色时回落到主题 primary', (tester) async {
    final control = await pumpSwitch(tester, value: true, onChanged: (_) {});
    final theme = Theme.of(tester.element(find.byType(FxSwitch)));
    expect(control.activeThumbColor, theme.colorScheme.primary);
  });

  testWidgets('onChanged 为空即禁用', (tester) async {
    final control = await pumpSwitch(tester, value: false, onChanged: null);
    expect(control.onChanged, isNull);
  });

  testWidgets('点一下能切，并且只回调一次', (tester) async {
    final values = <bool>[];
    await pumpSwitch(tester, value: false, onChanged: values.add);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(values, [true]);
  });
}
