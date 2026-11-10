import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/system_bars.dart';

/// 读取当前帧图层树里状态栏位置上的 overlay style。
///
/// Flutter 不是「设一次就全局生效」，而是每帧在图层树里按状态栏中心点
/// 找最近的 `AnnotatedRegion<SystemUiOverlayStyle>`。所以断言必须走
/// `Layer.find`，不能只看 widget 树里有没有那个 widget——widget 在、但
/// 被别的 region 盖住，结果照样是错的。
SystemUiOverlayStyle? _statusBarStyle(WidgetTester tester) {
  final view = tester.binding.renderViews.first;
  final top = Offset(
    view.paintBounds.center.dx,
    view.paintBounds.top + tester.view.padding.top / 2,
  );
  // `RenderObject.layer` 标了 @protected，业务代码本不该碰；这里是被测行为
  // 的唯一可观测入口——只有拿到真实图层树，才能断言「状态栏位置上到底有
  // 没有 overlay style」。widget 树里有没有那个 widget 完全说明不了问题。
  // ignore: invalid_use_of_protected_member
  return view.layer!.find<SystemUiOverlayStyle>(top);
}

void main() {
  group('KoyzeSystemBars', () {
    test('浅色主题给深色图标，深色主题给亮色图标', () {
      final light = KoyzeSystemBars.styleFor(Brightness.light);
      expect(light.statusBarIconBrightness, Brightness.dark);
      // iOS 语义相反：light 表示「背景亮」，也就是深色图标。
      expect(light.statusBarBrightness, Brightness.light);

      final dark = KoyzeSystemBars.styleFor(Brightness.dark);
      expect(dark.statusBarIconBrightness, Brightness.light);
      expect(dark.statusBarBrightness, Brightness.dark);
    });

    test('导航栏图标跟着状态栏一起换', () {
      expect(
        KoyzeSystemBars.styleFor(
          Brightness.light,
        ).systemNavigationBarIconBrightness,
        Brightness.dark,
      );
      expect(
        KoyzeSystemBars.styleFor(
          Brightness.dark,
        ).systemNavigationBarIconBrightness,
        Brightness.light,
      );
    });

    test('两种主题都不带系统对比度遮罩', () {
      // 透明状态栏下 Android 10+ 会自动垫一层半透明灰，浅色页面上是一道
      // 难看的带子；对比度交给图标颜色保证。
      for (final brightness in Brightness.values) {
        final style = KoyzeSystemBars.styleFor(brightness);
        expect(style.systemStatusBarContrastEnforced, isFalse);
        expect(style.systemNavigationBarContrastEnforced, isFalse);
        expect(style.statusBarColor, Colors.transparent);
      }
    });

    testWidgets('没有 AppBar 的页面也能拿到正确的状态栏样式', (tester) async {
      // 这就是线上那个 bug 的最小复现：一个没有 AppBar 的 Scaffold。
      // 修复前图层树里根本没有 overlay style，Flutter 不调
      // setSystemUIOverlayStyle，引擎停在默认的亮色图标上。
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: const KoyzeSystemBars(child: Scaffold(body: SizedBox.expand())),
        ),
      );
      await tester.pumpAndSettle();

      final style = _statusBarStyle(tester);
      expect(style, isNotNull, reason: '状态栏位置没有任何 overlay style，引擎会退回亮色图标');
      expect(style!.statusBarIconBrightness, Brightness.dark);
    });

    testWidgets('深色主题的根页面用亮色图标', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const KoyzeSystemBars(child: Scaffold(body: SizedBox.expand())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _statusBarStyle(tester)!.statusBarIconBrightness,
        Brightness.light,
      );
    });

    testWidgets('页面自己的 AppBar 仍然优先于兜底', (tester) async {
      // 兜底不能把子页面标题栏的判断压掉。深色 AppBar 上应当继续用亮色图标，
      // 哪怕外层兜底是浅色主题的深色图标。
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: KoyzeSystemBars(
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.black,
                systemOverlayStyle: SystemUiOverlayStyle.light,
              ),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _statusBarStyle(tester)!.statusBarIconBrightness,
        Brightness.light,
      );
    });

    testWidgets('DarkSystemBars 在浅色主题里也强制亮色图标', (tester) async {
      // 播放页就是这种情况：主题是浅色，但背景是封面压暗后的深色。
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: const KoyzeSystemBars(
            child: DarkSystemBars(child: Scaffold(body: SizedBox.expand())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _statusBarStyle(tester)!.statusBarIconBrightness,
        Brightness.light,
      );
    });
  });
}
