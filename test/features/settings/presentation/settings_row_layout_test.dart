import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:koyze/features/settings/presentation/settings_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 设置行的排版下限：窄屏（320dp）下整页要能排开。
///
/// 之前副标题没有行数约束，长句会折成三行，同一张卡片里的行高忽高忽低；
/// 更糟的是文案一长就会在窄屏上溢出。这里把两条都钉住。
void main() {
  Future<ProviderContainer> pumpSettings(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
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
        child: MaterialApp(
          // 用户看到的是中文界面，排版也按中文文案来验。
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('窄屏上整页排开且不溢出', (tester) async {
    // 320×2400：宽度取最窄的常见机型，高度拉大让懒加载列表把分组都建出来。
    await pumpSettings(tester, const Size(320, 2400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('副标题最多两行，长文案不会撑高整行', (tester) async {
    await pumpSettings(tester, const Size(320, 2400));

    final subtitles = tester
        .widgetList<Text>(find.byType(Text))
        .where((text) => text.style?.fontSize == 11.5)
        .where((text) => (text.data ?? '').isNotEmpty)
        .toList();

    expect(subtitles, isNotEmpty, reason: '设置页应该有副标题');
    for (final text in subtitles) {
      expect(text.maxLines, 2, reason: '副标题「${text.data}」必须限行，否则长句会把行撑成三行');
      expect(text.overflow, TextOverflow.ellipsis);
    }
  });

  testWidgets('点标题也能翻转开关，不用非得戳到右边那颗开关', (tester) async {
    final container = await pumpSettings(tester, const Size(390, 2600));

    // 「播放淡入淡出」在播放分区。只看翻转，不预设默认值。
    final before = container.read(playbackFadeEnabledProvider);
    await tester.tap(find.text('播放淡入淡出').first);
    await tester.pumpAndSettle();

    expect(
      container.read(playbackFadeEnabledProvider),
      !before,
      reason: '整行都应该能吃点击，否则用户会觉得这个开关是坏的',
    );
  });
}
