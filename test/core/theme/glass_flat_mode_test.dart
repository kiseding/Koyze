import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/performance/low_memory.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/theme/effect_policy.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/core/widgets/liquid_glass.dart';
import 'package:koyze/core/widgets/origo_chrome.dart';

/// 读某个材质最外层那块 DecoratedBox 的底色 alpha。
///
/// 界面不透明度最终就落在这一层上：调低就是 alpha 变小，不需要去猜像素。
double _surfaceAlpha(WidgetTester tester, Type type) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(of: find.byType(type), matching: find.byType(DecoratedBox)),
  );
  for (final box in boxes) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      return decoration.color!.a;
    }
  }
  fail('$type 下面没有带底色的 DecoratedBox');
}

/// 把被测材质放进带指定无障碍偏好的环境里。
Widget _host(
  Widget child, {
  bool highContrast = false,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          highContrast: highContrast,
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: Center(child: SizedBox(width: 320, height: 72, child: child)),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(() {
    LowMemory.active = false;
    GlassEffectConfig.setSurfaceOpacity(
      GlassEffectConfig.defaultSurfaceOpacity,
    );
  });

  group('GlassSurface', () {
    Widget surface() => GlassSurface(
      borderRadius: BorderRadius.circular(16),
      child: const Center(child: Text('玻璃')),
    );

    testWidgets('默认走透明度，不再采样背后', (tester) async {
      await tester.pumpWidget(_host(surface()));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('玻璃'), findsOneWidget);
    });

    testWidgets('增强对比度时退实色', (tester) async {
      await tester.pumpWidget(_host(surface(), highContrast: true));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('玻璃'), findsOneWidget);
    });

    testWidgets('系统关掉动画时退实色', (tester) async {
      await tester.pumpWidget(_host(surface(), disableAnimations: true));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('淡出变体同样不采样', (tester) async {
      Widget fading() => const GlassSurface(
        style: AppGlassStyle.bar,
        fade: AppGlassFade.up,
        child: Center(child: Text('底栏')),
      );
      await tester.pumpWidget(_host(fading()));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('底栏'), findsOneWidget);
    });

    testWidgets('只有显式 blurBehind 才采样（全屏播放器专用）', (tester) async {
      Widget panel({required bool blurBehind}) => GlassSurface(
        borderRadius: BorderRadius.circular(16),
        blurBehind: blurBehind,
        child: const Center(child: Text('面板')),
      );

      await tester.pumpWidget(_host(panel(blurBehind: false)));
      expect(find.byType(BackdropFilter), findsNothing);

      await tester.pumpWidget(_host(panel(blurBehind: true)));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('染色浓度', () {
    testWidgets('没有模糊时浓度更高，才压得住背后的列表', (tester) async {
      late Color plain;
      late Color blurred;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              plain = AppGlass.fillColor(context);
              blurred = AppGlass.fillColor(context, blurred: true);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(plain.a, greaterThan(blurred.a));
      // 播放器那档保持原值，不在这次改动里被动变浓。
      expect(blurred.a, closeTo(0.30, 0.001));
    });
  });

  group('LiquidGlassSurface', () {
    Widget capsule() => LiquidGlassSurface(
      borderRadius: BorderRadius.circular(22),
      child: const Center(child: Text('胶囊')),
    );

    testWidgets('默认只做透明混合', (tester) async {
      await tester.pumpWidget(_host(capsule()));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('胶囊'), findsOneWidget);
    });

    testWidgets('增强对比度时退实色', (tester) async {
      await tester.pumpWidget(_host(capsule(), highContrast: true));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('胶囊'), findsOneWidget);
    });

    testWidgets('滚动期 Minimal 档保留静态玻璃但不采样背后', (tester) async {
      await tester.pumpWidget(
        _host(
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(22),
            quality: GlassQuality.minimal,
            child: const Center(child: Text('轻量胶囊')),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('轻量胶囊'), findsOneWidget);
    });

    testWidgets('Standard 档默认也不采样，只有播放器可以显式打开', (tester) async {
      await tester.pumpWidget(
        _host(
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(22),
            quality: GlassQuality.standard,
            child: const Center(child: Text('标准胶囊')),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);

      // 显式 opt-in：只有全屏播放器这一层允许实时模糊。
      await tester.pumpWidget(
        _host(
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(22),
            quality: GlassQuality.standard,
            blurBehind: true,
            child: const Center(child: Text('播放器胶囊')),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('关闭背后采样兼容旧调用方式', (tester) async {
      await tester.pumpWidget(
        _host(
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(22),
            backdrop: false,
            child: const Center(child: Text('静态胶囊')),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('静态胶囊'), findsOneWidget);
    });
  });

  group('GradientFrost', () {
    Widget frost() => const GradientFrost(child: SizedBox.expand());

    testWidgets('默认不采样背后', (tester) async {
      await tester.pumpWidget(_host(frost()));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('增强对比度时退实色', (tester) async {
      await tester.pumpWidget(_host(frost(), highContrast: true));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('sigma 为 0 时本来就不采样', (tester) async {
      await tester.pumpWidget(
        _host(const GradientFrost(sigma: 0, child: SizedBox.expand())),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('界面不透明度', () {
    // 设置页的滑杆改的是全局静态档位。外层路由不会因此重建，所以每块玻璃面
    // 必须自己监听——否则就是"拖了没反应，回上一页才变"。
    testWidgets('GlassSurface 不重建父级也会当场变透', (tester) async {
      await tester.pumpWidget(
        _host(
          GlassSurface(
            borderRadius: BorderRadius.circular(16),
            child: const Center(child: Text('卡片')),
          ),
        ),
      );
      final before = _surfaceAlpha(tester, GlassSurface);

      GlassEffectConfig.setSurfaceOpacity(0.4);
      await tester.pump();

      final after = _surfaceAlpha(tester, GlassSurface);
      expect(after, lessThan(before));
      expect(after, closeTo(before * 0.5, 0.02));
    });

    testWidgets('迷你播放条用的液态玻璃同样当场变透', (tester) async {
      await tester.pumpWidget(
        _host(
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(22),
            child: const Center(child: Text('迷你栏')),
          ),
        ),
      );
      final before = _surfaceAlpha(tester, LiquidGlassSurface);

      GlassEffectConfig.setSurfaceOpacity(0.4);
      await tester.pump();

      final after = _surfaceAlpha(tester, LiquidGlassSurface);
      expect(after, closeTo(before * 0.5, 0.02));
    });

    testWidgets('顶栏染色跟着变，不会留一条旧浓度的标题栏', (tester) async {
      await tester.pumpWidget(
        _host(const GradientFrost(child: SizedBox.expand())),
      );
      double firstStop() {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(GradientFrost),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return ((box.decoration as BoxDecoration).gradient! as LinearGradient)
            .colors
            .first
            .a;
      }

      final before = firstStop();

      GlassEffectConfig.setSurfaceOpacity(0.4);
      await tester.pump();

      expect(firstStop(), closeTo(before * 0.5, 0.02));
    });

    testWidgets('顶栏在 100% 时不再渐隐，真正压住底下的列表', (tester) async {
      await tester.pumpWidget(
        _host(const GradientFrost(child: SizedBox.expand())),
      );

      GlassEffectConfig.setSurfaceOpacity(1);
      await tester.pump();

      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GradientFrost),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final gradient =
          (box.decoration as BoxDecoration).gradient! as LinearGradient;
      for (final color in gradient.colors) {
        expect(color.a, 1.0, reason: '顶栏还留着透明的渐隐段');
      }
    });

    testWidgets('拖到 100% 是完全实色，不是「设计浓度乘一」', (tester) async {
      await tester.pumpWidget(
        _host(
          GlassSurface(
            borderRadius: BorderRadius.circular(16),
            child: const Center(child: Text('卡片')),
          ),
        ),
      );

      GlassEffectConfig.setSurfaceOpacity(1);
      await tester.pump();

      expect(_surfaceAlpha(tester, GlassSurface), 1.0);
    });

    testWidgets('液态玻璃与顶栏在 100% 时同样归为实色', (tester) async {
      await tester.pumpWidget(
        _host(
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(22),
            child: const Center(child: Text('迷你栏')),
          ),
        ),
      );

      GlassEffectConfig.setSurfaceOpacity(1);
      await tester.pump();

      expect(_surfaceAlpha(tester, LiquidGlassSurface), 1.0);
      expect(
        GlassEffectConfig.chromeOpacityFor(Brightness.dark),
        1.0,
        reason: '顶栏走的也是同一套换算',
      );
      expect(
        GlassEffectConfig.chromeOpacityFor(Brightness.light, blurred: true),
        1.0,
      );
    });

    testWidgets('关掉玻璃效果时固定回实色，不受滑杆影响', (tester) async {
      await tester.pumpWidget(
        _host(
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(22),
            child: const Center(child: Text('胶囊')),
          ),
          highContrast: true,
        ),
      );
      final before = _surfaceAlpha(tester, LiquidGlassSurface);

      GlassEffectConfig.setSurfaceOpacity(0.4);
      await tester.pump();

      expect(_surfaceAlpha(tester, LiquidGlassSurface), closeTo(before, 0.001));
    });
  });
}
