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

    testWidgets('默认仍然采样背后', (tester) async {
      await tester.pumpWidget(_host(surface()));
      expect(find.byType(BackdropFilter), findsOneWidget);
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

    testWidgets('淡出变体同样退实色', (tester) async {
      Widget fading() => const GlassSurface(
        style: AppGlassStyle.bar,
        fade: AppGlassFade.up,
        child: Center(child: Text('底栏')),
      );
      await tester.pumpWidget(_host(fading()));
      expect(find.byType(BackdropFilter), findsOneWidget);

      await tester.pumpWidget(_host(fading(), highContrast: true));
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('LiquidGlassSurface', () {
    Widget capsule() => LiquidGlassSurface(
      borderRadius: BorderRadius.circular(22),
      child: const Center(child: Text('胶囊')),
    );

    testWidgets('默认仍然采样背后', (tester) async {
      await tester.pumpWidget(_host(capsule()));
      expect(find.byType(BackdropFilter), findsOneWidget);
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

    testWidgets('Standard 档仍然保留实时采样', (tester) async {
      await tester.pumpWidget(
        _host(
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(22),
            quality: GlassQuality.standard,
            child: const Center(child: Text('标准胶囊')),
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

    testWidgets('默认仍然采样背后', (tester) async {
      await tester.pumpWidget(_host(frost()));
      expect(find.byType(BackdropFilter), findsOneWidget);
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
