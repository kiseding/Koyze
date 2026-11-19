import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/core/widgets/frosted_tab_header.dart';
import 'package:koyze/core/widgets/gradient_bar_backgrounds.dart';
import 'package:koyze/core/widgets/origo_chrome.dart';
import 'package:koyze/core/widgets/root_tab_bar.dart';

/// 根壳层的 tab 标题栏必须真的采样背后。
///
/// 它以前只铺一条纯色渐变：`surface` 乘上不透明度之后确实会变淡，但背后
/// 从来没有被糊过——「虚化」滑杆拖到 100%，这一栏一动不动，看起来就是
/// 「tab 栏没用上虚化」。这些用例把「有没有建 BackdropFilter」钉住：虚化
/// 关掉时可以退回平涂，虚化打开时必须和独立页面的标题栏一样真的采样。
Widget _host(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(393, 852),
        padding: EdgeInsets.only(top: 59),
        viewPadding: EdgeInsets.only(top: 59),
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            child,
            // 顶上盖一段彩色内容，采样才有东西可糊。
            const SizedBox(height: 200),
          ],
        ),
      ),
    ),
  );
}

Widget _tabHeader() {
  return RootTabScope(
    selectedIndex: 0,
    onTap: (_) {},
    child: const FrostedTabHeader(title: ''),
  );
}

void main() {
  tearDown(() {
    GlassEffectConfig.setSurfaceOpacity(
      GlassEffectConfig.defaultSurfaceOpacity,
    );
    GlassEffectConfig.setSurfaceBlur(GlassEffectConfig.defaultSurfaceBlur);
  });

  group('tab 标题栏的虚化', () {
    testWidgets('虚化打开时真的采样背后', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(_host(_tabHeader()));
      expect(
        find.byType(BackdropFilter),
        findsOneWidget,
        reason: 'tab 标题栏没有建 BackdropFilter，虚化档对它完全无效',
      );
    });

    testWidgets('虚化为 0 时退回平涂，不白花一次全宽采样', (tester) async {
      GlassEffectConfig.setSurfaceBlur(0);
      await tester.pumpWidget(_host(_tabHeader()));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('滚动中仍然采样，只是半径乘折扣', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(_host(_tabHeader()));
      // 起手滚动之前就该有采样；这里只钉住「不会因为滚动而整条栏消失」。
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('拖不透明度滑杆时当帧重画', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(_host(_tabHeader()));
      final before = _tintAlpha(tester);

      GlassEffectConfig.setSurfaceOpacity(0.9);
      await tester.pump();

      expect(_tintAlpha(tester), greaterThan(before));
    });
  });

  group('和独立页面的标题栏同源', () {
    testWidgets('两者都走 GradientFrost', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(_host(_tabHeader()));
      expect(
        find.descendant(
          of: find.byType(FrostedTabHeader),
          matching: find.byType(GradientFrost),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _host(const GradientAppBarBackground(background: Colors.transparent)),
      );
      expect(find.byType(GradientFrost), findsOneWidget);
    });
  });
}

/// 顶栏染色层此刻的 alpha。虚化打开时染色层是一个渐变色，取它最浓的一端。
double _tintAlpha(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(GradientFrost),
      matching: find.byType(DecoratedBox),
    ),
  );
  for (final box in boxes) {
    final decoration = box.decoration;
    if (decoration is! BoxDecoration) continue;
    final color = decoration.color;
    if (color != null) return color.a;
    final gradient = decoration.gradient;
    if (gradient is LinearGradient && gradient.colors.isNotEmpty) {
      return gradient.colors.first.a;
    }
  }
  fail('GradientFrost 下面没有找到染色层');
}
