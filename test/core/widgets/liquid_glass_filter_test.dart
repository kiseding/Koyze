import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/core/widgets/glass_backdrop.dart';
import 'package:koyze/core/widgets/liquid_glass_filter.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 液态玻璃：开关状态、往回退的那条路，以及圆角折算。
///
/// **这套测试跑在 `flutter_tester` 上，它的
/// `ui.ImageFilter.isShaderFilterSupported` 恒为 false**，所以着色器永远编译
/// 不出来、`GlassEffectConfig.liquidGlass` 永远为 false。这是刻意的：玻璃面
/// 在真实后端上才有折射，这里能验的是「不可用时不崩、且准确退回普通毛玻璃」。
/// 折射本身的效果只能在设备上看（`flutter run --profile`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(
    () =>
        GlassEffectConfig.setLiquidGlass(GlassEffectConfig.defaultLiquidGlass),
  );

  group('着色器不可用时的退化', () {
    test('测试环境本身就不支持背景着色器滤镜', () {
      // 这条断言是给后来者看的：如果哪天 flutter_tester 支持了，下面那些
      // 「退回毛玻璃」的用例就不再成立，需要改成显式关闭着色器再验。
      expect(LiquidGlassShader.available, isFalse);
      expect(GlassEffectConfig.liquidGlass, isFalse);
    });

    testWidgets('仍画一整块毛玻璃，而不是留一块透明板', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassBackdrop(
              sigma: 12,
              allowBlur: true,
              radius: 16,
              child: SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );

      expect(find.byType(LiquidGlassBackdrop), findsNothing);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('开关打开也照样退回', (tester) async {
      GlassEffectConfig.setLiquidGlass(true);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassBackdrop(
              sigma: 12,
              allowBlur: true,
              radius: 0,
              child: SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );

      expect(find.byType(LiquidGlassBackdrop), findsNothing);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('没有圆角信息时不走液态玻璃', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassBackdrop(
              sigma: 12,
              allowBlur: true,
              child: SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );

      expect(find.byType(LiquidGlassBackdrop), findsNothing);
    });
  });

  group('着色器本身', () {
    test('引擎能加载，且 uniform 布局与写入顺序一致', () async {
      // 注意：`flutter_tester` 的 `isShaderFilterSupported` 是 false，但
      // FragmentProgram 照样能加载。所以这一条验的是「着色器语法与参数表」，
      // 不是「折射画出来了」——后者只能在设备上看。
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      final shader = program.fragmentShader();

      // 0、1 是引擎填写的输入纹理尺寸；2..17 是 RenderLiquidGlass.paint 里
      // 按顺序写的 16 个参数（玻璃宽高、圆角、像素比、边缘厚度、折射、色散、
      // 高光、色调、圆角指数、原点 xy、留边、色调色 rgb）。
      for (var index = 0; index < 18; index++) {
        expect(
          () => shader.setFloat(index, 1),
          returnsNormally,
          reason: 'uniform $index 越界，说明 shader 的参数表比 Dart 侧短',
        );
      }
      // 第 19 个必须越界。哪天往 shader 里加了 uniform 却忘了在 paint 里补
      // setFloat（或改了顺序），这条会先拦下来。
      expect(() => shader.setFloat(18, 1), throwsRangeError);
    });
  });

  group('圆角折算', () {
    test('四角同半径才折算得出', () {
      expect(uniformGlassRadius(BorderRadius.circular(12)), 12);
      expect(uniformGlassRadius(BorderRadius.zero), 0);
    });

    test('上圆下方的面板折算不出来', () {
      // 底部面板常见形状：着色器只认一个半径，硬套会让折射边和裁剪对不上。
      expect(
        uniformGlassRadius(
          const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        isNull,
      );
    });

    test('椭圆角折算不出来', () {
      expect(
        uniformGlassRadius(const BorderRadius.all(Radius.elliptical(12, 8))),
        isNull,
      );
    });
  });

  group('开关状态', () {
    test('默认打开', () {
      expect(GlassEffectConfig.defaultLiquidGlass, isTrue);
      expect(GlassEffectConfig.liquidGlassPreferred, isTrue);
    });

    test('整体关闭玻璃效果时不生效', () {
      GlassEffectConfig.setDisableAllGlassEffects(true);
      addTearDown(() => GlassEffectConfig.setDisableAllGlassEffects(false));

      expect(GlassEffectConfig.liquidGlassPreferred, isFalse);
      expect(GlassEffectConfig.liquidGlass, isFalse);
    });

    test('改了会通知已经建好的玻璃面', () {
      var notified = 0;
      void listener() => notified++;
      GlassEffectConfig.liquidGlassListenable.addListener(listener);
      addTearDown(
        () => GlassEffectConfig.liquidGlassListenable.removeListener(listener),
      );

      GlassEffectConfig.setLiquidGlass(false);
      expect(notified, 1);

      // 写同一个值不该再触发一次重建。
      GlassEffectConfig.setLiquidGlass(false);
      expect(notified, 1);
    });

    test('虚化折算：满档也只到「柔和」材质的量级', () {
      // 顶栏基线 15 × 模糊系数 0.85 ≈ 12.75，折算后约 3.8。
      expect(GlassEffectConfig.liquidFrost(12.75), closeTo(3.825, 0.001));
      // 0 档就是完全清透，纯靠折射成形。
      expect(GlassEffectConfig.liquidFrost(0), 0);
    });
  });

  group('持久化', () {
    Future<StorageService> storageWith(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return StorageService.forTesting(await SharedPreferences.getInstance());
    }

    test('空存储退到出厂值（开）', () async {
      final storage = await storageWith(<String, Object>{});
      final notifier = LiquidGlassNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.value, GlassEffectConfig.defaultLiquidGlass);
    });

    test('读回关闭状态', () async {
      final storage = await storageWith({'liquid_glass_enabled': false});
      final notifier = LiquidGlassNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.value, isFalse);
    });

    test('切换会落盘', () async {
      final storage = await storageWith(<String, Object>{});
      final notifier = LiquidGlassNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      notifier.setEnabled(false);
      await Future<void>.delayed(Duration.zero);

      expect(storage.getBool('liquid_glass_enabled'), isFalse);
      expect(notifier.value, isFalse);
    });
  });
}
