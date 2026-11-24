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
import 'package:koyze/features/player/presentation/player_provider.dart';
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

/// 引擎能力由运行时现算（`audioHandler` 是 late 全局变量，启动早期还没初始化），
/// 所以测试只能覆盖这个判断本身，而不是去伪造一整台播放引擎。
Widget _appWithCapabilities(
  EqualizerBridge bridge,
  StorageService storage, {
  bool enhancement = false,
}) => ProviderScope(
  overrides: [
    equalizerBridgeProvider.overrideWithValue(bridge),
    equalizerStorageProvider.overrideWithValue(() async => storage),
    audioEnhancementSupportedProvider.overrideWithValue(enhancement),
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

    expect(bridge.applies.last.gains, <double>[5, 4, 0, -4, -5]);
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('+4'), findsOneWidget);
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

    expect(find.text('-5'), findsWidgets);

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

  testWidgets('交叉馈送 / 响度 / 限幅都在这一页，且各自判断能力', (tester) async {
    // 增强项排在均衡器下面，默认 800×600 的视口装不下，ListView 也不会
    // 把没滚到的子项建出来。用高视口一次全建出来，按文字断言即可。
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = await _freshStorage();
    await tester.pumpWidget(
      _appWithCapabilities(
        FakeEqualizerBridge(layout: fiveBandLayout),
        storage,
        enhancement: true,
      ),
    );
    await tester.pumpAndSettle();

    // 这三项以前在「设置 > 播放」里，和淡入淡出、跳过静音挤在一起。
    // 它们改的是声音本身，现在和均衡器同页——调音色不用来回跳两页。
    expect(find.text('Audio enhancement'), findsOneWidget);
    expect(find.text('Crossfeed'), findsOneWidget);
    expect(find.text('Loudness leveling'), findsOneWidget);
    expect(find.text('Clipping protection'), findsOneWidget);
    // 频谱是纯视觉项，已经回到设置页的「播放」区，这一页不该再有入口。
    expect(find.text('Live spectrum'), findsNothing);
    // 强度只在交叉馈送开着时才出现，和设置页里的从属关系一致。
    expect(find.text('Crossfeed strength'), findsNothing);

    // 打开交叉馈送：强度行随之出现，滑块拖动直接写设置（边听边调）。
    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Crossfeed'),
              matching: find.byType(Row),
            ),
            matching: find.byType(FxSwitch),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Crossfeed strength'), findsOneWidget);
  });

  testWidgets('引擎不支持时整段不渲染，而不是留一排拨了没反应的开关', (tester) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = await _freshStorage();
    await tester.pumpWidget(
      _appWithCapabilities(
        FakeEqualizerBridge(layout: fiveBandLayout),
        storage,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Audio enhancement'), findsNothing);
    expect(find.text('Crossfeed'), findsNothing);
    // 均衡器本身仍可用：能力判断是各自独立的，不是整页一刀切。
    expect(find.byType(Slider), findsNWidgets(5));
  });

  testWidgets('均衡器不可用不影响音频增强：它们是各自的能力', (tester) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = await _freshStorage();
    await tester.pumpWidget(
      _appWithCapabilities(
        FakeEqualizerBridge(supported: false),
        storage,
        enhancement: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Equalizer is not available here'), findsOneWidget);
    // iOS 上没有均衡器实现，但 mpv 的 af 链照常可用——整页当一个开关会
    // 把本来能用的功能一起藏掉。
    expect(find.text('Crossfeed'), findsOneWidget);
  });
}
