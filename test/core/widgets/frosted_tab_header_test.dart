import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/effect_policy.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/core/widgets/frosted_tab_header.dart';
import 'package:koyze/core/widgets/glass_backdrop.dart';
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
    testWidgets('虚化打开时整条背板采样', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(_host(_tabHeader()));
      expect(
        find.descendant(
          of: find.byType(GradientFrost),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
        reason: 'tab 标题栏没有建 BackdropFilter，虚化档对它完全无效',
      );
    });

    testWidgets('虚化为 0 时退回平涂，不白花一次全宽采样', (tester) async {
      GlassEffectConfig.setSurfaceBlur(0);
      await tester.pumpWidget(_host(_tabHeader()));
      expect(
        find.descendant(
          of: find.byType(GradientFrost),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    });

    testWidgets('虚化由全宽背板承担，胶囊不另采样', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(_host(_tabHeader()));
      expect(
        find.descendant(
          of: find.byType(RootTabBar),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(find.byType(BackdropFilter), findsOneWidget);

      final filter = tester.getRect(find.byType(BackdropFilter));
      expect(filter.topLeft, Offset.zero);
      expect(filter.width, tester.getSize(find.byType(FrostedTabHeader)).width);
      expect(filter.height, 59 + FrostedTabHeader.barHeight);
    });

    testWidgets('滚动中与停手后半径一致，不跟着手势变', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      addTearDown(GlassScrollActivity.reset);
      await tester.pumpWidget(_host(_tabHeader()));
      final idle = _backdropSigma(tester);

      // 只置位不会触发重建（现在的实现已经不监听它了），所以手动把
      // GradientFrost 标脏再 pump——模拟「滚动中这一帧真的重建了」。
      // 少了这一步，即使实现里读 `isScrolling` 也测不出来。
      GlassScrollActivity.set(true);
      _rebuildFrost(tester);
      await tester.pump();
      final scrolling = _backdropSigma(tester);

      GlassScrollActivity.set(false);
      _rebuildFrost(tester);
      await tester.pump();

      // 早先滚动期 sigma 乘 0.5，手指一抬模糊度就跳一下。更糟的是独立页面
      // 的标题栏不在 `GlassScrollObserver` 范围内（它只包了根壳层），所以
      // 同一个组件在 tab 里会变、在收藏列表里不变——同一套材质两种观感。
      expect(scrolling, idle, reason: '滚动期把标题栏半径打了折，停手时会看到模糊度跳变');
      expect(_backdropSigma(tester), idle);
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

    testWidgets('模糊半径和独立页面一致', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(_host(_tabHeader()));
      final tabSigma = _frost(tester).sigma;

      await tester.pumpWidget(
        _host(const GradientAppBarBackground(background: Colors.transparent)),
      );
      final appBarSigma = _frost(tester).sigma;

      // tab 栏早先取 `AppGlass.blurChrome`（15 × 0.85 = 12.75），独立页面
      // 取写死的 16。并排看就是两种材质，所以钉住这个相等关系。
      expect(tabSigma, appBarSigma);
      expect(tabSigma, GradientAppBarBackground.defaultBlur);
    });

    testWidgets('染色层是纯色，没有栏下渐隐', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      GlassEffectConfig.setSurfaceOpacity(0.65);
      await tester.pumpWidget(_host(_tabHeader()));

      // 早先 tab 栏比栏本体高 28pt 并把那一截淡出到 0，导致栏下三分之一是
      // 半透明的，滚到那里的封面会透上来。收藏列表没有这截渐隐，两相对比
      // 就显出「tab 栏更淡」。现在两边都是纯色平涂。
      final layer = _tintLayer(tester);
      expect(layer.color, isNotNull, reason: '染色层不该是渐变');
      expect(layer.gradient, isNull);
    });

    testWidgets('背景层高度就是栏本体，不多留一截', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(_host(_tabHeader()));

      final top = 59.0; // _host 里的状态栏高度
      final frostBox = tester.getSize(
        find.descendant(
          of: find.byType(FrostedTabHeader),
          matching: find.byType(GradientFrost),
        ),
      );
      expect(frostBox.height, top + FrostedTabHeader.barHeight);
    });
  });
}

/// 当前树里第一个 [GradientFrost]（tab 栏和独立页面各自只有一个）。
GradientFrost _frost(WidgetTester tester) {
  return tester.widget<GradientFrost>(find.byType(GradientFrost).first);
}

/// 标题栏此刻真正喂给 `BackdropFilter` 的高斯半径。
double _backdropSigma(WidgetTester tester) {
  final backdrop = tester.widget<GlassBackdrop>(
    find
        .descendant(
          of: find.byType(GradientFrost),
          matching: find.byType(GlassBackdrop),
        )
        .first,
  );
  return backdrop.sigma;
}

/// 把 [GradientFrost] 标脏，逼它重新走一遍 build。
void _rebuildFrost(WidgetTester tester) {
  tester.element(find.byType(GradientFrost).first).markNeedsBuild();
}

/// [GradientFrost] 里那层染色（Stack 的最上层之外，直接带 color/gradient 的盒子）。
BoxDecoration _tintLayer(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(GradientFrost),
      matching: find.byType(DecoratedBox),
    ),
  );
  for (final box in boxes) {
    final decoration = box.decoration;
    if (decoration is! BoxDecoration) continue;
    if (decoration.color != null || decoration.gradient != null) {
      return decoration;
    }
  }
  fail('GradientFrost 下面没有找到染色层');
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
