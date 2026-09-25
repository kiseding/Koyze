import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/widgets/fx_switch.dart';
import 'package:koyze/features/equalizer/domain/equalizer_preset.dart';
import 'package:koyze/features/equalizer/domain/equalizer_settings.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'equalizer_test_support.dart';

String _englishPreset(String id) => switch (id) {
  'flat' => 'Flat',
  'pop' => 'Pop',
  'rock' => 'Rock',
  'jazz' => 'Jazz',
  'classical' => 'Classical',
  'electronic' => 'Electronic',
  'folk' => 'Folk',
  'vocal' => 'Vocal',
  'bass' => 'Bass boost',
  'treble' => 'Treble boost',
  _ => 'Custom',
};

/// 每个测试用独立的存储，避免 StorageService 的静态实例串数据。
Future<StorageService> _freshStorage() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return StorageService.forTesting(await SharedPreferences.getInstance());
}

Future<StorageService> _storageSeeded(EqualizerSettings settings) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    equalizerSettingsStorageKey: json.encode(settings.toJson()),
  });
  return StorageService.forTesting(await SharedPreferences.getInstance());
}

Widget _app(EqualizerBridge bridge, StorageService storage) => ProviderScope(
  overrides: [
    equalizerBridgeProvider.overrideWithValue(bridge),
    equalizerStorageProvider.overrideWithValue(() async => storage),
  ],
  child: const MaterialApp(home: EqualizerScreen()),
);

void main() {
  testWidgets('不支持的平台只给出说明，不渲染频段', (tester) async {
    final storage = await _freshStorage();
    await tester.pumpWidget(
      _app(FakeEqualizerBridge(supported: false), storage),
    );
    await tester.pumpAndSettle();

    expect(find.text('Equalizer is not available here'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Bass boost'), findsNothing);
  });

  testWidgets('支持的平台渲染全部预设与频段滑块', (tester) async {
    final storage = await _freshStorage();
    await tester.pumpWidget(
      _app(FakeEqualizerBridge(layout: fiveBandLayout), storage),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNWidgets(5));
    for (final preset in equalizerPresets) {
      expect(find.text(_englishPreset(preset.id)), findsOneWidget);
    }
    expect(find.text('Custom'), findsNothing, reason: '未手动调整时不出现');
    // 关闭状态下滑块不可拖动。
    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);
    expect(find.text('Turn the equalizer on to adjust'), findsOneWidget);
    expect(find.textContaining('Device bands: 5'), findsOneWidget);
  });

  testWidgets('开启开关后滑块可拖动，选预设会推给音频层', (tester) async {
    final storage = await _freshStorage();
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);
    await tester.pumpWidget(_app(bridge, storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FxSwitch));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Slider>(find.byType(Slider).first).onChanged,
      isNotNull,
    );
    expect(bridge.applies.last.enabled, isTrue);

    await tester.tap(find.text('Bass boost'));
    await tester.pumpAndSettle();

    expect(bridge.applies.last.gains, <double>[3, 1.5, -1, -2, -2.5]);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('+1.5'), findsOneWidget);
    // 预设选择已落盘。
    expect(
      EqualizerSettings.fromJson(
        storage.getJson(equalizerSettingsStorageKey)!,
      ).presetId,
      'bass',
    );
  });

  testWidgets('拖动频段后切到自定义', (tester) async {
    final storage = await _storageSeeded(
      const EqualizerSettings(
        enabled: true,
        presetId: 'flat',
        gains: <double>[0, 0, 0, 0, 0],
      ),
    );
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);
    await tester.pumpWidget(_app(bridge, storage));
    await tester.pumpAndSettle();

    expect(find.text('Turn the equalizer on to adjust'), findsNothing);

    final slider = find.byType(Slider).at(1);
    await tester.drag(slider, const Offset(0, -30));
    await tester.pumpAndSettle();

    final saved = EqualizerSettings.fromJson(
      storage.getJson(equalizerSettingsStorageKey)!,
    );
    expect(saved.presetId, kCustomPresetId);
    expect(saved.gains[1], greaterThan(0));
    expect(saved.gains[0], 0, reason: '其它频段不受影响');
    expect(bridge.applies.last.gains[1], saved.gains[1]);
    expect(find.text('Custom'), findsOneWidget, reason: '手动调整后出现提示');
  });

  testWidgets('播放器未激活时用兜底布局并给出提示', (tester) async {
    final storage = await _storageSeeded(
      const EqualizerSettings(enabled: true, presetId: 'bass'),
    );
    await tester.pumpWidget(_app(FakeEqualizerBridge(), storage));
    await tester.pumpAndSettle();

    expect(
      find.byType(Slider),
      findsNWidgets(kFallbackEqualizerLayout.bandCount),
    );
    expect(find.textContaining('Player not connected'), findsOneWidget);
  });

  testWidgets('重置把频段归零', (tester) async {
    final storage = await _storageSeeded(
      const EqualizerSettings(
        enabled: true,
        presetId: 'rock',
        gains: <double>[4, 2, -1, 2, 3],
      ),
    );
    final bridge = FakeEqualizerBridge(layout: fiveBandLayout);
    await tester.pumpWidget(_app(bridge, storage));
    await tester.pumpAndSettle();

    expect(find.text('-3'), findsWidgets);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    final saved = EqualizerSettings.fromJson(
      storage.getJson(equalizerSettingsStorageKey)!,
    );
    expect(saved.presetId, kDefaultPresetId);
    expect(saved.gains, List<double>.filled(5, 0));
    expect(bridge.applies.last.gains, List<double>.filled(5, 0));
  });

  testWidgets('10 段设备按真实段数渲染', (tester) async {
    final storage = await _storageSeeded(
      const EqualizerSettings(enabled: true, presetId: 'treble'),
    );
    await tester.pumpWidget(
      _app(FakeEqualizerBridge(layout: tenBandLayout), storage),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNWidgets(10));
    expect(find.textContaining('Device bands: 10'), findsOneWidget);
  });
}
