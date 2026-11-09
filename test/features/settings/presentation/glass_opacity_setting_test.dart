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

  tearDown(() => GlassEffectConfig.setSurfaceOpacity(1));

  Future<StorageService> storageWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return StorageService.forTesting(await SharedPreferences.getInstance());
  }

  test('an empty store keeps the shipped opacity', () async {
    final storage = await storageWith(<String, Object>{});
    final notifier = GlassOpacityNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value, 1);
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

  test('the setting actually scales the glass tint', () {
    final blurredBefore = GlassEffectConfig.chromeOpacityFor(
      Brightness.dark,
      blurred: true,
    );
    final plainBefore = GlassEffectConfig.chromeOpacityFor(Brightness.dark);

    GlassEffectConfig.setSurfaceOpacity(0.5);

    expect(
      GlassEffectConfig.chromeOpacityFor(Brightness.dark, blurred: true),
      closeTo(blurredBefore * 0.5, 0.001),
    );
    expect(
      GlassEffectConfig.chromeOpacityFor(Brightness.dark),
      closeTo(plainBefore * 0.5, 0.001),
    );
  });

  testWidgets('AppGlass.fillColor honours the multiplier', (tester) async {
    late Color full;
    late Color half;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            GlassEffectConfig.setSurfaceOpacity(1);
            full = AppGlass.fillColor(context);
            GlassEffectConfig.setSurfaceOpacity(0.5);
            half = AppGlass.fillColor(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(half.a, closeTo(full.a * 0.5, 0.001));
  });
}
