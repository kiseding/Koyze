import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 界面材质的统一不透明度：默认值、越界收敛、拖动时的「立刻生效 + 合并落盘」，
/// 以及它确实会缩放玻璃面的染色浓度。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(
    () => GlassEffectConfig.setSurfaceOpacity(
      GlassEffectConfig.defaultSurfaceOpacity,
    ),
  );

  Future<StorageService> storageWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return StorageService.forTesting(await SharedPreferences.getInstance());
  }

  test('an empty store keeps the shipped opacity', () async {
    final storage = await storageWith(<String, Object>{});
    final notifier = GlassOpacityNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value, GlassEffectConfig.defaultSurfaceOpacity);
  });

  test('values below the floor are clamped on load', () async {
    final storage = await storageWith({'glass_surface_opacity': -3.0});
    final notifier = GlassOpacityNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value, GlassEffectConfig.minSurfaceOpacity);
  });

  test('dragging applies at once and writes once after it settles', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final notifier = GlassOpacityNotifier(
      storage: () async => StorageService.forTesting(prefs),
    );

    notifier
      ..setOpacity(0.8)
      ..setOpacity(0.6)
      ..setOpacity(0.45);

    expect(notifier.value, 0.45);
    expect(prefs.getDouble(GlassOpacityNotifier.storageKey), isNull);

    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(prefs.getDouble(GlassOpacityNotifier.storageKey), 0.45);
  });

  test('the slider percentage is the alpha itself, with no curve', () {
    // 选 45% 就画 0.45。以前这里要按各材质的基础浓度分两段换算，同一个数字
    // 在顶栏、卡片、菜单上会显示成四种深浅，滑杆等于白调。
    for (final value in [0.3, 0.45, 0.6, 0.8, 0.93]) {
      GlassEffectConfig.setSurfaceOpacity(value);
      expect(GlassEffectConfig.surfaceAlpha, closeTo(value, 1e-9));
    }
  });

  test('the top of the slider is genuinely solid', () {
    GlassEffectConfig.setSurfaceOpacity(1);
    expect(GlassEffectConfig.surfaceAlpha, 1.0);
  });

  testWidgets('AppGlass.fillColor honours the multiplier', (tester) async {
    late Color full;
    late Color half;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            GlassEffectConfig.setSurfaceOpacity(
              GlassEffectConfig.defaultSurfaceOpacity,
            );
            full = AppGlass.fillColor(context);
            GlassEffectConfig.setSurfaceOpacity(0.4);
            half = AppGlass.fillColor(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      full.a,
      closeTo(GlassEffectConfig.defaultSurfaceOpacity, 0.001),
      reason: '默认档就是 0.95，不是 0.82 或 0.66',
    );
    expect(half.a, closeTo(0.4, 0.001));
  });
}
