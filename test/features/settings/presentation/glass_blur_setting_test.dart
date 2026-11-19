import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「虚化」这一档：出厂 0、越界收敛、倍率而非 sigma、拖动时的「立刻生效 +
/// 合并落盘」，以及它确实驱动玻璃面重画。
///
/// 这一档的默认值从 0（关）改成了 0.9（接近满档）：原先「关上更省」的考虑
/// 建立在「只有播放器允许模糊」那套观感上，现在虚化本身就是用户可调的外观
/// 项，出厂关着会让第一次打开设置页的人以为开关坏了。0 仍然是个合法值，
/// 拖到底就退回「这一档上线前」的观感。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(
    () =>
        GlassEffectConfig.setSurfaceBlur(GlassEffectConfig.defaultSurfaceBlur),
  );

  Future<StorageService> storageWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return StorageService.forTesting(await SharedPreferences.getInstance());
  }

  test(
    'an empty store falls back to the shipped default, not to zero',
    () async {
      final storage = await storageWith(<String, Object>{});
      final notifier = GlassBlurNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.value, GlassEffectConfig.defaultSurfaceBlur);
      // 出厂就是满档虚化的：用户没动过滑杆时，界面也该是毛玻璃而不是一片实色。
      expect(notifier.value, 1.0);
    },
  );

  test('values below the floor and non-finite values fall back', () async {
    for (final stored in <double>[-3.0, double.nan, double.infinity]) {
      final storage = await storageWith({'glass_surface_blur': stored});
      final notifier = GlassBlurNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      expect(
        notifier.value,
        GlassEffectConfig.minSurfaceBlur,
        reason: '存进去的 $stored 要收敛到 0',
      );
    }
  });

  test('values above one are clamped on load', () async {
    final storage = await storageWith({'glass_surface_blur': 7.5});
    final notifier = GlassBlurNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value, 1.0);
  });

  test('dragging applies at once and writes once after it settles', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final notifier = GlassBlurNotifier(
      storage: () async => StorageService.forTesting(prefs),
    );

    notifier
      ..setBlur(0.9)
      ..setBlur(0.5)
      ..setBlur(0.35);

    expect(notifier.value, 0.35);
    expect(prefs.getDouble(GlassBlurNotifier.storageKey), isNull);

    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(prefs.getDouble(GlassBlurNotifier.storageKey), 0.35);
  });

  test('the setting is a multiplier, not a sigma', () {
    // 各材质本来就有自己的基线半径，这一档只统一缩放它们。同一个 50% 在
    // 顶栏和弹窗上的实际糊度不同，但「更糊了」的方向一致。
    const sigma = 20.0;
    for (final value in <double>[0, 0.25, 0.5, 1]) {
      GlassEffectConfig.setSurfaceBlur(value);
      expect(
        GlassEffectConfig.scaleSurfaceBlur(sigma),
        closeTo(sigma * value, 1e-9),
      );
    }
  });

  test('zero is still a valid setting: same look as before this slider', () {
    // 0 不再是默认值，但用户把滑杆拖到底时仍然要回到「这一档上线前」的观感：
    // 半透明染色、不采样背后，而不是变成一块实色。
    GlassEffectConfig.setSurfaceBlur(0);

    expect(GlassEffectConfig.userBlurEnabled, isFalse);
    expect(GlassEffectConfig.scaleSurfaceBlur(24), 0);
    // 不透明度不受牵连：两档互相独立，不换算。
    GlassEffectConfig.setSurfaceOpacity(0.6);
    expect(GlassEffectConfig.surfaceAlpha, closeTo(0.6, 1e-9));
  });

  test('turning off all glass effects zeroes the blur', () {
    GlassEffectConfig.setSurfaceBlur(0.8);
    expect(GlassEffectConfig.userBlurEnabled, isTrue);

    GlassEffectConfig.setDisableAllGlassEffects(true);
    addTearDown(() => GlassEffectConfig.setDisableAllGlassEffects(false));

    expect(GlassEffectConfig.surfaceBlur, 0);
    expect(GlassEffectConfig.userBlurEnabled, isFalse);
    expect(GlassEffectConfig.scaleSurfaceBlur(20), 0);
  });

  test(
    'changing the value notifies surfaces even when nobody rebuilds them',
    () {
      // 滑杆在设置页，玻璃面在别的路由下；光改静态字段不会让它们重画，
      // 靠的就是这个信号。
      var fired = 0;
      void listener() => fired++;
      GlassEffectConfig.surfaceBlurListenable.addListener(listener);
      addTearDown(
        () => GlassEffectConfig.surfaceBlurListenable.removeListener(listener),
      );

      GlassEffectConfig.setSurfaceBlur(0.4);
      expect(fired, 1);
      expect(GlassEffectConfig.surfaceBlur, 0.4);

      // 同一个值重复设置不该产生多余的重画。
      GlassEffectConfig.setSurfaceBlur(0.4);
      expect(fired, 1);

      GlassEffectConfig.setSurfaceBlur(0.7);
      expect(fired, 2);
    },
  );

  test('the blur signal is independent from the opacity signal', () {
    var opacityFired = 0;
    void opacityListener() => opacityFired++;
    GlassEffectConfig.surfaceOpacityListenable.addListener(opacityListener);
    addTearDown(
      () => GlassEffectConfig.surfaceOpacityListenable.removeListener(
        opacityListener,
      ),
    );

    GlassEffectConfig.setSurfaceBlur(0.5);

    expect(opacityFired, 0, reason: '动虚化不该惊动只有不透明度的那些面');
  });

  testWidgets('AppGlass.fillColor ignores the blur level', (tester) async {
    late Color sharp;
    late Color frosted;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            GlassEffectConfig.setSurfaceOpacity(0.8);
            GlassEffectConfig.setSurfaceBlur(0);
            sharp = AppGlass.fillColor(context);
            GlassEffectConfig.setSurfaceBlur(0.9);
            frosted = AppGlass.fillColor(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // 糊不糊是另一回事，染色浓度只由不透明度决定。
    expect(frosted.a, closeTo(sharp.a, 1e-9));
    expect(sharp.a, closeTo(0.8, 0.001));
  });
}
