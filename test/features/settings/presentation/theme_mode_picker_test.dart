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

/// 「主题」是三态单选，不是两个互相打架的开关。
///
/// 之前外观分区并排放着「深色模式」和「跟随系统」两颗开关，两者写同一个
/// ThemeMode：打开跟随系统会把深色拨回去，打开深色又会让跟随系统灭掉。
/// 用户按下其中一颗、另一颗自己弹回来，看起来就是「设置没生效」。
void main() {
  testWidgets('主题是一个三选一，选完立刻落到 themeMode', (tester) async {
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
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('主题'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    // 三个选项同时在。用各自的说明文案定位，避免和页面上同名的
    // 「跟随系统」副标题（语言也有一份）撞车。
    expect(find.text('始终使用浅色主题'), findsOneWidget);
    expect(find.text('使用深色主题'), findsOneWidget);
    expect(find.text('自动切换亮色/深色主题'), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
    // 行上的副标题随之变成当前值。
    expect(find.text('深色'), findsOneWidget);
  });
}
