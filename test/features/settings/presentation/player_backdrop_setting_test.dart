import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/player/domain/player_backdrop.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放页背景的两档设置：默认值、越界收敛、拖动时的「立刻生效 + 合并落盘」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> storageWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return StorageService.forTesting(await SharedPreferences.getInstance());
  }

  test('an empty store keeps the shipped backdrop', () async {
    final storage = await storageWith(<String, Object>{});
    final blur = PlayerBackdropBlurNotifier(storage: () async => storage);
    final scrim = PlayerBackdropScrimNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(blur.value, PlayerBackdrop.defaultBlur);
    expect(scrim.value, PlayerBackdrop.defaultScrim);
  });

  test('stored values outside the range are clamped on load', () async {
    final storage = await storageWith({
      'player_backdrop_blur': 400.0,
      'player_backdrop_scrim': -2.0,
    });
    final blur = PlayerBackdropBlurNotifier(storage: () async => storage);
    final scrim = PlayerBackdropScrimNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(blur.value, PlayerBackdrop.maxBlur);
    expect(scrim.value, PlayerBackdrop.minScrim);
  });

  test('dragging applies at once and writes once after it settles', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final notifier = PlayerBackdropBlurNotifier(
      storage: () async => StorageService.forTesting(prefs),
    );

    notifier
      ..setBlur(70)
      ..setBlur(80)
      ..setBlur(95);

    // 界面必须跟手：拖动中读到的就是最新值。
    expect(notifier.value, 95);
    // 但盘上一次都还没写——否则一秒钟会有几十次异步写。
    expect(prefs.getDouble('player_backdrop_blur'), isNull);

    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(prefs.getDouble('player_backdrop_blur'), 95);
  });

  test('reset writes the default without waiting for the debounce', () async {
    SharedPreferences.setMockInitialValues({'player_backdrop_scrim': 0.2});
    final prefs = await SharedPreferences.getInstance();
    final notifier = PlayerBackdropScrimNotifier(
      storage: () async => StorageService.forTesting(prefs),
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifier.value, 0.2);

    await notifier.commitScrim(PlayerBackdrop.defaultScrim);

    expect(notifier.value, PlayerBackdrop.defaultScrim);
    expect(
      prefs.getDouble('player_backdrop_scrim'),
      PlayerBackdrop.defaultScrim,
    );
  });

  test('a pending drag is flushed when the notifier goes away', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final notifier = PlayerBackdropBlurNotifier(
      storage: () async => StorageService.forTesting(prefs),
    );

    notifier.setBlur(30);
    // 用户刚拖到的值不能因为页面销毁而丢掉。
    notifier.flush();

    await Future<void>.delayed(Duration.zero);
    expect(prefs.getDouble('player_backdrop_blur'), 30);
  });
}
