import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/widgets/frosted_tab_header.dart';
import 'package:koyze/core/widgets/fx_switch.dart';
import 'package:koyze/core/widgets/root_shell_layout.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/search/presentation/search_controls.dart';
import 'package:koyze/features/settings/presentation/settings_entry.dart';
import 'package:koyze/features/settings/presentation/settings_screen.dart';
import 'package:koyze/features/settings/presentation/settings_search_layer.dart';

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The layer on its own, over rows the test controls.
void main() {
  testWidgets('typing narrows the rows down to the matching ones', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final activated = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsSearchLayer(
            sections: const [
              SettingsSectionSpec(
                title: 'Playback',
                entries: [
                  SettingsEntry(
                    title: 'Sleep timer',
                    subtitle: 'Off',
                    keywords: ['睡眠', 'timer'],
                    onTap: _noop,
                  ),
                  SettingsEntry(
                    title: 'Audio quality',
                    subtitle: 'High (320 kbps)',
                    keywords: ['flac'],
                    onTap: _noop,
                  ),
                ],
              ),
              SettingsSectionSpec(
                title: 'Appearance',
                entries: [
                  SettingsEntry(
                    title: 'Language',
                    subtitle: 'English',
                    onTap: _noop,
                  ),
                ],
              ),
            ],
            topInset: 0,
            bottomInset: 0,
            onClose: _noop,
            onActivate: (entry) => activated.add(entry.title),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 空查询就是一份目录：所有行都在，按分区排。
    expect(find.text('Sleep timer'), findsOneWidget);
    expect(find.text('Audio quality'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Playback'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'sleep');
    await tester.pumpAndSettle();
    expect(find.text('Sleep timer'), findsOneWidget);
    expect(find.text('Audio quality'), findsNothing);
    expect(find.text('Appearance'), findsNothing);

    // 中文关键词也能命中，不必是标题里的字。
    await tester.enterText(find.byType(TextField), '睡眠');
    await tester.pumpAndSettle();
    expect(find.text('Sleep timer'), findsOneWidget);
    expect(find.text('Language'), findsNothing);

    await tester.enterText(find.byType(TextField), 'kbps');
    await tester.pumpAndSettle();
    expect(find.text('Audio quality'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching settings'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'language');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    expect(activated, ['Language']);
  });

  testWidgets('a switch row flips in the results instead of navigating', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final toggles = <bool>[];
    final activated = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsSearchLayer(
            sections: [
              SettingsSectionSpec(
                title: 'Appearance',
                entries: [
                  SettingsEntry(
                    title: 'Dark mode',
                    subtitle: 'Follow the system',
                    keywords: const ['night'],
                    toggleValue: false,
                    onToggle: toggles.add,
                  ),
                ],
              ),
            ],
            topInset: 0,
            bottomInset: 0,
            onClose: _noop,
            onActivate: (entry) => activated.add(entry.title),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dark');
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);

    await tester.tap(find.byType(FxSwitch));
    await tester.pumpAndSettle();
    expect(toggles, [true]);
    // 开关行留在原地，不会被当成导航行推走。
    expect(activated, isEmpty);
  });

  // 窄屏（小手机）和宽屏（桌面 / 横屏车机）都要能把一行摆下：副标题最长的那条
  // 加上右侧的箭头，任何一头溢出都会被这条用例抓住。
  for (final size in const [Size(320, 568), Size(1024, 600)]) {
    testWidgets('a result row fits at ${size.width.toInt()}px wide', (
      tester,
    ) async {
      _setViewport(tester, size);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingsSearchLayer(
              sections: [
                SettingsSectionSpec(
                  title: 'Playback',
                  entries: [
                    SettingsEntry(
                      title: 'Reduce effects',
                      subtitle:
                          'Turn off frosted glass, transparency, and motion. '
                          'On by default at 4GB or less',
                      toggleValue: true,
                      onToggle: _ignoreToggle,
                    ),
                    SettingsEntry(
                      title: 'Audio quality',
                      subtitle: 'High (320 kbps)',
                      onTap: _noop,
                    ),
                  ],
                ),
              ],
              topInset: 0,
              bottomInset: 0,
              onClose: _noop,
              onActivate: _noop2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 有输入时输入框右侧还会长出一对圆形按钮，这是最挤的状态。
      await tester.enterText(find.byType(TextField), 'reduce');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Reduce effects'), findsOneWidget);
      expect(find.byType(FxSwitch), findsOneWidget);
    });
  }

  testWidgets('the header button opens search and the row it finds runs', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
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
        sleepTimerProvider.overrideWith(
          () => SleepTimerNotifier(() async {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final headers = RootHeaderController();
    addTearDown(headers.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RootHeaderScope(
            controller: headers,
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: headers,
                  builder: (context, _) => Row(
                    children: headers.headerFor(3)?.actions ?? const [],
                  ),
                ),
                const Expanded(child: SettingsScreen()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSearchLayer), findsOneWidget);
    expect(find.byType(SearchFieldBar), findsOneWidget);
    // 开着搜索时，右上角那颗按钮变成关闭。
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'audio quality');
    await tester.pumpAndSettle();
    final results = find.byType(SettingsSearchLayer);
    expect(
      find.descendant(of: results, matching: find.text('Audio quality')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: results, matching: find.text('Language')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: results, matching: find.text('Audio quality')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSearchLayer), findsNothing);
    expect(find.text('Choose quality'), findsOneWidget);
  });

  testWidgets('search closes from the header and leaves the list untouched', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
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
        sleepTimerProvider.overrideWith(
          () => SleepTimerNotifier(() async {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final headers = RootHeaderController();
    addTearDown(headers.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RootHeaderScope(
            controller: headers,
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: headers,
                  builder: (context, _) => Row(
                    children: headers.headerFor(3)?.actions ?? const [],
                  ),
                ),
                const Expanded(child: SettingsScreen()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'language');
    await tester.pumpAndSettle();

    // 有输入时输入框里也有一颗清除叉，顶栏那颗要按容器认。
    await tester.tap(
      find.descendant(
        of: find.byType(FrostedHeaderButton),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSearchLayer), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    // 列表还在原处：第一屏那一行没被搜索层带走。
    expect(find.text('Cloud account'), findsOneWidget);
  });
}

void _noop() {}

void _noop2(SettingsEntry entry) {}

void _ignoreToggle(bool value) {}
