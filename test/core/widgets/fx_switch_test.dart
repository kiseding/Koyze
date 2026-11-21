import 'dart:ui' show SemanticsAction, Tristate;

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

  testWidgets('开关按 kSwitchVisualScale 等比缩小', (tester) async {
    await pumpSwitch(tester, value: true, onChanged: (_) {});

    // 布局盒仍是平台的 60×40，缩小发生在绘制矩阵上。
    expect(tester.getSize(find.byType(Switch)), kSwitchIntrinsicSize);

    final painted = MatrixUtils.transformRect(
      tester.renderObject<RenderBox>(find.byType(Switch)).getTransformTo(null),
      Offset.zero & kSwitchIntrinsicSize,
    );
    expect(painted.width, closeTo(kSwitchIntrinsicSize.width * 0.88, 0.01));
    expect(painted.height, closeTo(kSwitchIntrinsicSize.height * 0.88, 0.01));
  });

  testWidgets('缩放只动绘制，点按范围不变小', (tester) async {
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => FxSwitch(
                value: value,
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );

    // 点在未缩放盒子的左上角、缩放后轨道之外的那一圈：仍然要能切。
    // 这一圈在缩放前属于 tap 目标，缩放后视觉上已经空出来，但命中区域
    // 没跟着缩——触屏上点偏一点仍然有效。
    final rect = tester.getRect(find.byType(Switch));
    await tester.tapAt(rect.topLeft + const Offset(3, 3));
    await tester.pumpAndSettle();
    expect(value, isTrue);
  });

  group('FxSwitchTile', () {
    Future<void> pumpTile(
      WidgetTester tester, {
      required bool value,
      ValueChanged<bool>? onChanged,
      double scale = 1,
      String title = '设置项',
      String? subtitle,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: Center(
              child: FxSwitchTile(
                value: value,
                onChanged: onChanged,
                title: Text(title),
                subtitle: subtitle == null ? null : Text(subtitle),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('开关同样是缩小的那一颗', (tester) async {
      await pumpTile(tester, value: true, onChanged: (_) {});
      expect(find.byType(Switch), findsOneWidget);

      final painted = MatrixUtils.transformRect(
        tester
            .renderObject<RenderBox>(find.byType(Switch))
            .getTransformTo(null),
        Offset.zero & kSwitchIntrinsicSize,
      );
      expect(painted.height, closeTo(40 * kSwitchVisualScale, 0.01));
    });

    testWidgets('点标题也能翻转，且只回调一次', (tester) async {
      final values = <bool>[];
      await pumpTile(tester, value: false, onChanged: values.add, title: '淡出');
      await tester.tap(find.text('淡出'));
      await tester.pumpAndSettle();
      expect(values, [true]);
    });

    testWidgets('点开关本身也只回调一次，不会翻两下', (tester) async {
      final values = <bool>[];
      await pumpTile(tester, value: false, onChanged: values.add);

      // 开关被 `IgnorePointer` 包着，这一点按会穿透到外层行；`warnIfMissed`
      // 正是要关掉——「点击没打到开关上」就是这里要验证的行为，不是失误。
      await tester.tap(find.byType(Switch), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(values, [true]);
    });

    testWidgets('副标题参与合并语义，且不会被念成「按钮」', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTile(
        tester,
        value: true,
        onChanged: (_) {},
        title: '跳过重复',
        subtitle: '同一首歌只留一份',
      );

      // 标题与副标题并入同一条语义节点；`isButton` 必须是 false——
      // 否则读屏会念成「按钮」而不是「开关，已打开」。
      final data = tester
          .getSemantics(find.byType(FxSwitchTile))
          .getSemanticsData();
      expect(data.label, '跳过重复\n同一首歌只留一份');
      expect(data.flagsCollection.isToggled, Tristate.isTrue);
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('禁用时整行不响应', (tester) async {
      await pumpTile(tester, value: false, onChanged: null, title: '禁用项');

      // ListTile 的 onTap 不再承担点击（改由外层 InkWell），
      // 所以这里断言的是「外层没挂手势 + 语义上禁用」。
      expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);
      // 外层那颗 InkWell 不该挂手势（Switch 内部自己也有一个，
      // 所以要从 FxSwitchTile 往下取第一层）。
      final outerInkWell = tester.widget<InkWell>(
        find
            .descendant(
              of: find.byType(FxSwitchTile),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(outerInkWell.onTap, isNull);

      await tester.tap(find.text('禁用项'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget);
    });
  });
}
