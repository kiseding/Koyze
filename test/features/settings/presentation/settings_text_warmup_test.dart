import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/settings/presentation/settings_entry.dart';
import 'package:koyze/features/settings/presentation/settings_screen.dart';
import 'package:koyze/features/settings/presentation/settings_text_warmup.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 文本预热：把「首次滑动时那几十行中文第一次排版」的成本提前到空闲帧。
///
/// 背景见 `settings_text_warmup.dart` 的文件注释——真机上首滑那一秒只有
/// 4~13fps 而 GPU 只有 5~12%，瓶颈在 UI 线程。这里锁住三件事：预热覆盖到
/// 哪些文案、页面打开后确实排了、以及进程内只排一次。
void main() {
  setUp(SettingsTextWarmUp.resetForTesting);
  tearDown(SettingsTextWarmUp.resetForTesting);

  group('预热范围', () {
    test('收进每一行的标题与副标题，跳过空副标题', () {
      const sections = [
        SettingsSectionSpec(
          title: '播放',
          entries: [
            SettingsEntry(title: '音质', subtitle: '标准'),
            SettingsEntry(title: '均衡器'),
          ],
        ),
        SettingsSectionSpec(
          title: '通用',
          entries: [SettingsEntry(title: '语言', subtitle: '跟随系统')],
        ),
      ];

      expect(SettingsTextWarmUp.stringsFor(sections), [
        '音质',
        '标准',
        '均衡器',
        '语言',
        '跟随系统',
      ]);
    });

    test('分区标题不在预热范围内', () {
      const sections = [
        SettingsSectionSpec(
          title: '只该出现一次的分区名',
          entries: [SettingsEntry(title: '行标题')],
        ),
      ];

      expect(
        SettingsTextWarmUp.stringsFor(sections),
        isNot(contains('只该出现一次的分区名')),
      );
    });

    test('同一进程只排一次', () {
      const sections = [
        SettingsSectionSpec(
          title: '播放',
          entries: [
            SettingsEntry(title: '音质', subtitle: '标准'),
          ],
        ),
      ];

      void schedule() => SettingsTextWarmUp.schedule(
        sections: sections,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxWidth: 300,
      );

      schedule();
      final first = SettingsTextWarmUp.debugLayouts;
      expect(first, 2, reason: '一条标题一条副标题，各 layout 一次');
      expect(SettingsTextWarmUp.scheduled, isTrue);

      schedule();
      expect(SettingsTextWarmUp.debugLayouts, first, reason: '重复调用不该再排版');
    });

    test('宽度非正时不排，也不把状态钉成已排', () {
      const sections = [
        SettingsSectionSpec(
          title: '播放',
          entries: [SettingsEntry(title: '音质')],
        ),
      ];

      SettingsTextWarmUp.schedule(
        sections: sections,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxWidth: 0,
      );

      expect(SettingsTextWarmUp.scheduled, isFalse);
      expect(SettingsTextWarmUp.debugLayouts, 0);
    });
  });

  testWidgets('打开设置页后会把这一页的文案排一遍', (tester) async {
    tester.view.physicalSize = const Size(390, 2600);
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

    expect(SettingsTextWarmUp.scheduled, isTrue);
    // 第一块是同步跑的：即使用户在下一帧就开始拖，也已经热了一部分。
    expect(SettingsTextWarmUp.debugLayouts, greaterThan(0));
  });
}
