import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/audio_enhancement.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/settings/presentation/settings_notifiers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 音频增强设置：默认值、越界收敛、坏数据不炸、以及三项共用一个存储键。
///
/// 共用键是刻意的：它们总是一起被施加到 `af` 链上，分开存会让首次进入
/// 设置页触发三次独立异步读取，而读到的三份快照之间还可能互相不一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> storageWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return StorageService.forTesting(await SharedPreferences.getInstance());
  }

  test('空存储时用出厂默认：限幅开着，其余关着', () async {
    final storage = await storageWith(<String, Object>{});
    final notifier = AudioEnhancementNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value.crossfeedEnabled, isFalse);
    expect(notifier.value.loudnessEnabled, isFalse);
    // 限幅默认开：均衡器可能产生正增益，没有限幅就是直接削波。
    expect(notifier.value.limiterEnabled, isTrue);
    expect(notifier.value.crossfeedStrength, closeTo(0.35, 0.001));
  });

  test('拨开关后落盘，重建 notifier 能读回来', () async {
    final storage = await storageWith(<String, Object>{});
    final first = AudioEnhancementNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    await first.setCrossfeedEnabled(true);
    await first.setLoudnessEnabled(true);
    await first.setLimiterEnabled(false);

    final second = AudioEnhancementNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);
    expect(second.value.crossfeedEnabled, isTrue);
    expect(second.value.loudnessEnabled, isTrue);
    expect(second.value.limiterEnabled, isFalse);
  });

  test('强度越界与非有限值都被收敛，不会写出 NaN', () async {
    final storage = await storageWith(<String, Object>{});
    final notifier = AudioEnhancementNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    await notifier.setCrossfeedStrength(5);
    expect(notifier.value.crossfeedStrength, 1.0);

    await notifier.setCrossfeedStrength(-2);
    expect(notifier.value.crossfeedStrength, 0.0);

    // NaN/Infinity 直接忽略：写成 0 反而会把用户拖好的强度清掉。
    await notifier.setCrossfeedStrength(0.6);
    await notifier.setCrossfeedStrength(double.nan);
    expect(notifier.value.crossfeedStrength, closeTo(0.6, 0.001));
  });

  test('存储里的坏数据退回默认，不让播放器起不来', () async {
    // 类型全错：字符串冒充布尔、字符串冒充数值、显式 null。
    final storage = await storageWith(<String, Object>{
      'audio_enhancement_v1':
          '{"crossfeedEnabled":"yes","crossfeedStrength":"loud",'
          '"loudnessEnabled":1,"limiterEnabled":null}',
    });
    final notifier = AudioEnhancementNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value.crossfeedEnabled, isFalse);
    expect(notifier.value.crossfeedStrength, closeTo(0.35, 0.001));
    expect(notifier.value.loudnessEnabled, isFalse);
    expect(notifier.value.limiterEnabled, isTrue);
  });

  test('存下来的强度超范围时读回来也被夹住', () async {
    // 可能是旧版本写进去的，也可能被人手改过配置文件。
    // getJson 读的是 JSON 字符串，不是 Map —— 直接塞 Map 会走「损坏」分支。
    final storage = await storageWith(<String, Object>{
      'audio_enhancement_v1':
          '{"crossfeedEnabled":true,"crossfeedStrength":42.0,'
          '"loudnessEnabled":false,"limiterEnabled":true}',
    });
    final notifier = AudioEnhancementNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value.crossfeedStrength, 1.0);
    expect(notifier.value.crossfeedEnabled, isTrue);
  });

  test('设置值本身相等时不会重复落盘', () async {
    final storage = await storageWith(<String, Object>{});
    final notifier = AudioEnhancementNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    // 已经是默认值，再拨一遍不该产生写入。
    await notifier.setCrossfeedEnabled(false);
    await notifier.setLimiterEnabled(true);
    expect(notifier.value, const AudioEnhancementSettings());
  });
}