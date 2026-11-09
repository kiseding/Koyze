import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/features/settings/presentation/terms_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

import '../../../support/source_text.dart';

/// 条款页要够长、够完整，且只出现在设置里——它不再是启动时的闸门。
Future<void> _pumpTerms(
  WidgetTester tester, {
  Locale locale = const Locale('zh'),
}) async {
  // 八节正文在 390 宽下远超一屏，把视口拉高让 ListView 一次建完，
  // 免去逐段滚动；否则后面的小节根本没被 build，断言会假阴性。
  // 英文译本比中文长，视口按英文的行数留足。
  tester.view.physicalSize = const Size(390, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.lightTheme(),
      home: const TermsScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

const _zhSectionTitles = [
  '一、本应用的性质',
  '二、内容来源与权利归属',
  '三、第三方音源脚本',
  '四、使用规范',
  '五、数据与隐私',
  '六、免责声明',
  '七、条款的变更与终止',
  '八、其他',
];

void main() {
  testWidgets('八节条款依次呈现', (tester) async {
    await _pumpTerms(tester);

    for (final title in _zhSectionTitles) {
      expect(find.text(title), findsOneWidget, reason: '缺少小节：$title');
    }
  });

  testWidgets('正文写清了产品边界，而不是一句话免责', (tester) async {
    await _pumpTerms(tester);

    expect(find.text('用户条款与免责声明'), findsOneWidget);
    expect(find.textContaining('最后更新'), findsOneWidget);
    // 四条核心边界：不提供内容、不取得授权、脚本不受控、按现状提供。
    expect(find.textContaining('不运营曲库'), findsOneWidget);
    expect(find.textContaining('亦不代任何用户取得授权'), findsOneWidget);
    expect(find.textContaining('由第三方作者编写和维护'), findsOneWidget);
    expect(find.textContaining('本应用按现状提供'), findsOneWidget);
    expect(find.textContaining('以中文文本为准'), findsOneWidget);
  });

  testWidgets('页面上没有任何同意控件——它只是一份文档', (tester) async {
    await _pumpTerms(tester);

    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('同意并继续'), findsNothing);
    expect(find.text('我已阅读并同意上述条款'), findsNothing);
  });

  testWidgets('英文环境渲染对应译本', (tester) async {
    await _pumpTerms(tester, locale: const Locale('en'));

    expect(find.text('Terms of Use and Disclaimer'), findsOneWidget);
    expect(find.text('6. Disclaimer'), findsOneWidget);
    expect(find.text('8. Miscellaneous'), findsOneWidget);
  });

  test('启动路径上不再挂条款闸门', () {
    final app = readSource('lib/app.dart');
    expect(app, isNot(contains('FirstRunGate')));
    expect(app, isNot(contains('first_run_gate')),
        reason: '首启闸门已移除，启动时不该再有任何条款拦截');
  });

  test('设置最底部留了条款入口', () {
    final settings = readSource(
      'lib/features/settings/presentation/settings_screen.dart',
    );
    expect(settings, contains("context.push('/terms')"));
    expect(settings, contains('s.termsTitle'));
  });
}
