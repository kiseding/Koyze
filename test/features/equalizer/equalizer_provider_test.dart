import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/equalizer/domain/equalizer_preset.dart';
import 'package:koyze/features/equalizer/domain/equalizer_settings.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'equalizer_test_support.dart';

Future<StorageService> _storageFrom(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return StorageService.forTesting(await SharedPreferences.getInstance());
}

String _encoded(EqualizerSettings settings) => json.encode(settings.toJson());

void main() {
  test('读取已保存的设置并施加到音频层', () async {
    final storage = await _storageFrom(<String, Object>{
      equalizerSettingsStorageKey: _encoded(
        const EqualizerSettings(
          enabled: true,
          presetId: 'bass',
          gains: <double>[6, 4, 1, 0, 0],
        ),
      ),
    });
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);

    final notifier = EqualizerNotifier(
      bridge: bridge,
      storage: () async => storage,
    );
    await notifier.restored;

    expect(notifier.value.loading, isFalse);
    expect(notifier.value.supported, isTrue);
    expect(notifier.value.settings.enabled, isTrue);
    expect(notifier.value.settings.presetId, 'bass');
    expect(notifier.value.layout, fiveBandLayout);
    expect(notifier.value.gains, <double>[3, 1.5, -1, -2, -2.5]);
    expect(bridge.applies.single.enabled, isTrue);
    expect(bridge.applies.single.gains, <double>[3, 1.5, -1, -2, -2.5]);
  });

  test('没有保存过时使用默认值且不报错', () async {
    final storage = await _storageFrom(<String, Object>{});
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);

    final notifier = EqualizerNotifier(
      bridge: bridge,
      storage: () async => storage,
    );
    await notifier.restored;

    expect(notifier.value.settings, const EqualizerSettings());
    expect(notifier.value.settings.enabled, isFalse);
    expect(notifier.value.interactive, isFalse);
    expect(bridge.applies.single.enabled, isFalse);
  });

  test('开关与预设会写入存储', () async {
    final storage = await _storageFrom(<String, Object>{});
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);
    final notifier = EqualizerNotifier(
      bridge: bridge,
      storage: () async => storage,
    );
    await notifier.restored;

    await notifier.setEnabled(true);
    await notifier.selectPreset('treble');

    final saved = EqualizerSettings.fromJson(
      storage.getJson(equalizerSettingsStorageKey)!,
    );
    expect(saved.enabled, isTrue);
    expect(saved.presetId, 'treble');
    // 高音增强在 5 段布局上采样出的增益。
    expect(saved.gains, <double>[-2.5, -2, -1, 1.5, 3]);
    expect(bridge.applies.last.enabled, isTrue);
    expect(bridge.applies.last.gains, <double>[-2.5, -2, -1, 1.5, 3]);
  });

  test('拖动频段会切换成自定义并保留其它频段', () async {
    final storage = await _storageFrom(<String, Object>{
      equalizerSettingsStorageKey: _encoded(
        const EqualizerSettings(
          enabled: true,
          presetId: 'bass',
          gains: <double>[6, 4, 1, 0, 0],
        ),
      ),
    });
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);
    final notifier = EqualizerNotifier(
      bridge: bridge,
      storage: () async => storage,
    );
    await notifier.restored;

    await notifier.setBandGain(1, 7.5);

    expect(notifier.value.settings.isCustom, isTrue);
    expect(notifier.value.settings.presetId, kCustomPresetId);
    expect(notifier.value.gains, <double>[3, 7.5, -1, -2, -2.5]);
    expect(notifier.value.settings.presetLabel, '自定义');
  });

  test('频段增益被夹在设备允许范围内', () async {
    final storage = await _storageFrom(<String, Object>{});
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);
    final notifier = EqualizerNotifier(
      bridge: bridge,
      storage: () async => storage,
    );
    await notifier.restored;

    await notifier.setBandGain(0, 999);
    expect(notifier.value.gains[0], fiveBandLayout.maxDecibels);

    await notifier.setBandGain(0, -999);
    expect(notifier.value.gains[0], fiveBandLayout.minDecibels);

    // 越界索引直接忽略。
    await notifier.setBandGain(9, 3);
    expect(notifier.value.gains[0], fiveBandLayout.minDecibels);
  });

  test('重置回到原声但保留总开关', () async {
    final storage = await _storageFrom(<String, Object>{
      equalizerSettingsStorageKey: _encoded(
        const EqualizerSettings(
          enabled: true,
          presetId: 'rock',
          gains: <double>[4, 2, -1, 2, 3],
        ),
      ),
    });
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);
    final notifier = EqualizerNotifier(
      bridge: bridge,
      storage: () async => storage,
    );
    await notifier.restored;

    await notifier.resetToFlat();

    expect(notifier.value.settings.presetId, kDefaultPresetId);
    expect(notifier.value.gains, List<double>.filled(5, 0));
    expect(notifier.value.settings.enabled, isTrue);
  });

  test('布局未就绪时按兜底布局展示，就绪后替换', () async {
    final storage = await _storageFrom(<String, Object>{
      equalizerSettingsStorageKey: _encoded(
        const EqualizerSettings(enabled: true, presetId: 'bass'),
      ),
    });
    final bridge = FakeEqualizerBridge();
    final notifier = EqualizerNotifier(
      bridge: bridge,
      storage: () async => storage,
    );
    await notifier.restored;

    expect(notifier.value.layoutReady, isFalse);
    expect(notifier.value.effectiveLayout, kFallbackEqualizerLayout);
    expect(notifier.value.gains.length, kFallbackEqualizerLayout.bandCount);

    // 播放器激活后拿到真实布局：段数不同，增益按预设曲线重新采样。
    bridge.layout = tenBandLayout;
    await notifier.refreshLayout();

    expect(notifier.value.layoutReady, isTrue);
    expect(notifier.value.effectiveLayout, tenBandLayout);
    expect(notifier.value.gains.length, 10);
    expect(notifier.value.gains.first, closeTo(3, 0.5));
  });

  test('平台不支持时不施加但仍保留设置', () async {
    final storage = await _storageFrom(<String, Object>{});
    final bridge = FakeEqualizerBridge(supported: false);
    final notifier = EqualizerNotifier(
      bridge: bridge,
      storage: () async => storage,
    );
    await notifier.restored;

    expect(notifier.value.supported, isFalse);
    expect(notifier.value.interactive, isFalse);
    expect(bridge.applies, isEmpty);

    await notifier.setEnabled(true);
    await notifier.selectPreset('bass');

    expect(bridge.applies, isEmpty, reason: '没有实现就不该调用音频层');
    // 设置照常保存，换到支持的平台后依然生效。
    final saved = EqualizerSettings.fromJson(
      storage.getJson(equalizerSettingsStorageKey)!,
    );
    expect(saved.enabled, isTrue);
    expect(saved.presetId, 'bass');
  });

  test('读取损坏的存储数据时回落到默认值', () async {
    final storage = await _storageFrom(<String, Object>{
      equalizerSettingsStorageKey: '{ 这不是 JSON',
    });
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);
    final notifier = EqualizerNotifier(
      bridge: bridge,
      storage: () async => storage,
    );
    await notifier.restored;

    expect(notifier.value.loading, isFalse);
    expect(notifier.value.settings, const EqualizerSettings());
  });

  test('设置页副标题反映开关与预设', () async {
    expect(
      equalizerSubtitle(
        const EqualizerState(supported: false, settings: EqualizerSettings()),
      ),
      '当前平台不支持',
    );
    expect(
      equalizerSubtitle(
        const EqualizerState(supported: true, settings: EqualizerSettings()),
      ),
      '未开启',
    );
    expect(
      equalizerSubtitle(
        const EqualizerState(
          supported: true,
          settings: EqualizerSettings(enabled: true, presetId: 'rock'),
        ),
      ),
      '已开启 · 摇滚',
    );
  });
}
