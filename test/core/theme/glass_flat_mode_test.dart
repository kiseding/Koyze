import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/performance/low_memory.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/theme/effect_policy.dart';
import 'package:koyze/core/widgets/liquid_glass.dart';
import 'package:koyze/core/widgets/origo_chrome.dart';

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
  tearDown(() => LowMemory.active = false);

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
}
