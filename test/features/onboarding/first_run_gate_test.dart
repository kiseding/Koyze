import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/features/onboarding/presentation/first_run_gate.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 首启只剩一道门：读条款、勾选、继续。
/// 曾经的三步引导（条款 → 配音源 → 完成）已经去掉，这里钉住它不会悄悄回来。
Future<void> _pumpGate(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme(),
        home: const FirstRunGate(child: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('首启只展示用户条款', (tester) async {
    await _pumpGate(tester);

    expect(find.text('用户条款与免责声明'), findsOneWidget);
    expect(find.text('同意并继续'), findsOneWidget);
    expect(find.text('我已阅读并同意上述条款'), findsOneWidget);

    // 旧引导的步骤文案不该再出现
    expect(find.text('先添加一个音源'), findsNothing);
    expect(find.text('准备就绪'), findsNothing);
    expect(find.text('开始听歌'), findsNothing);
  });

  testWidgets('四条免责要点都完整呈现', (tester) async {
    await _pumpGate(tester);

    expect(find.textContaining('不存放、不上传、不分发'), findsOneWidget);
    expect(find.textContaining('权利归各平台与权利人所有'), findsOneWidget);
    expect(find.textContaining('第三方脚本'), findsOneWidget);
    expect(find.textContaining('只保存在本机'), findsOneWidget);
  });

  testWidgets('未勾选时不能继续，勾选后按钮可用', (tester) async {
    await _pumpGate(tester);

    FilledButton button() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '同意并继续'));

    expect(button().onPressed, isNull, reason: '未勾选同意时不该能进入应用');

    await tester.tap(find.text('我已阅读并同意上述条款'));
    await tester.pump();

    expect(button().onPressed, isNotNull, reason: '勾选后应放行');
  });

  testWidgets('条款页文字不带装饰线', (tester) async {
    await _pumpGate(tester);

    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      expect(
        text.text.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: '条款页出现了装饰线：${text.text.toPlainText()}',
      );
    }
  });
}
