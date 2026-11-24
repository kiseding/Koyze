import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:koyze/features/settings/presentation/settings_screen.dart';
import 'package:koyze/features/settings/presentation/settings_section_card.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 设置页的行高与「外观」分区的归位：
///
/// * 纯标题行、带副标题行、带开关行必须是同一个高度，不能再出现三级台阶；
/// * 不透明度和虚化合并成一行、点开面板才出现两根滑杆；
/// * 「跟随封面取色」收进强调色面板，列表里不再单占一行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    GlassEffectConfig.setSurfaceOpacity(
      GlassEffectConfig.defaultSurfaceOpacity,
    );
    GlassEffectConfig.setSurfaceBlur(GlassEffectConfig.defaultSurfaceBlur);
  });

  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 6000);
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
        playerSpectrumSupportedProvider.overrideWithValue(true),
        // 面板里的预览会读当前封面；测试里没有播放引擎，直接当作没在播。
        currentMusicProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  double rowHeight(WidgetTester tester, String label) {
    final row = find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    );
    expect(row, findsWidgets, reason: '「$label」不在任何一行里');
    return tester.getSize(row.first).height;
  }

  testWidgets('下载区的三行高度完全一致，且等于带副标题那一档', (tester) async {
    await pumpSettings(tester);

    final manage = rowHeight(tester, '下载管理');
    final quality = rowHeight(tester, '下载音质');
    final wifi = rowHeight(tester, '仅 Wi-Fi 下载');

    expect(quality, kSettingsRowMinHeight);
    expect(manage, quality, reason: '纯标题行不该比带副标题行矮');
    expect(wifi, quality, reason: '带开关行不该是第三种高度');
  });

  testWidgets('外观：两根滑杆收进「界面质感」面板', (tester) async {
    await pumpSettings(tester);

    // 列表里不再直接摆滑杆。
    expect(find.byType(Slider), findsNothing);
    expect(find.text('界面不透明度'), findsNothing);
    expect(find.text('界面质感'), findsOneWidget);

    await tester.tap(find.text('界面质感'));
    await tester.pumpAndSettle();

    expect(find.text('界面不透明度'), findsOneWidget);
    expect(find.text('虚化'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
  });

  testWidgets('拖动面板里的滑杆会即时改掉全局不透明度', (tester) async {
    final container = await pumpSettings(tester);

    await tester.tap(find.text('界面质感'));
    await tester.pumpAndSettle();

    final before = container.read(glassOpacityProvider);
    await tester.drag(find.byType(Slider).first, const Offset(-80, 0));
    await tester.pumpAndSettle();

    expect(container.read(glassOpacityProvider), lessThan(before));
    expect(
      GlassEffectConfig.surfaceAlpha,
      closeTo(container.read(glassOpacityProvider), 1e-9),
      reason: '拖动时要立刻写进静态配置，预览才能当帧变化',
    );
  });

  testWidgets('「跟随封面取色」搬进强调色面板', (tester) async {
    final container = await pumpSettings(tester);

    // 列表里已经不再单独占一行。
    expect(find.text('跟随封面取色'), findsNothing);

    await tester.tap(find.text('强调色'));
    await tester.pumpAndSettle();

    expect(find.text('跟随封面取色'), findsOneWidget);

    final before = container.read(coverThemedAccentProvider);
    await tester.tap(find.text('跟随封面取色'));
    await tester.pumpAndSettle();

    expect(container.read(coverThemedAccentProvider), !before);
  });
}
