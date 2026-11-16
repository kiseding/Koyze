import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/settings/presentation/settings_screen.dart';
import 'package:koyze/features/settings/presentation/settings_section_card.dart';

/// 设置页滚动掉帧的结构性护栏。
///
/// 掉帧不是 build 慢（实测每帧 build 0.5ms），而是**图层太大**：整张分区卡片
/// 曾经是一个 `RepaintBoundary`，一张卡 700~900pt 高、整屏宽，落到真实像素是
/// 近千万像素；滚动时引擎的栅格缓存装不下几块这么大的图层，逐帧重画整卡，
/// 于是滑动一顿一顿。现在列表不再自动加边界（`addRepaintBoundaries: false`），
/// 改成每一行自己一层。
void main() {
  testWidgets('设置列表把每一行拆成独立图层', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final container = ProviderContainer(
      overrides: [
        equalizerBridgeProvider.overrideWithValue(
          const UnsupportedEqualizerBridge(),
        ),
        equalizerStorageProvider.overrideWithValue(() async => storage),
        settingsDeviceIdProvider.overrideWith((ref) async => 'device_test'),
        sleepTimerProvider.overrideWith(() => SleepTimerNotifier(() async {})),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView).first);
    // ignore: avoid_dynamic_calls
    final delegate = listView.childrenDelegate;
    expect(delegate, isA<SliverChildListDelegate>());
    expect(
      (delegate as SliverChildListDelegate).addRepaintBoundaries,
      isFalse,
      reason: '整卡一层会把 700pt 高的内容压进同一个图层，栅格缓存装不下',
    );

    // 行本身仍然各有一层：滚动时位移由合成器完成，内容不重画。
    expect(
      find.descendant(
        of: find.byType(SettingsSectionCard).first,
        matching: find.byType(RepaintBoundary),
      ),
      findsAtLeastNWidgets(3),
    );
  });
}
