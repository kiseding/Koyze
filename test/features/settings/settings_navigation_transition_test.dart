import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/widgets/koyze_sheet.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:koyze/features/settings/presentation/settings_screen.dart';

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('setting pickers use one floating glass dialog rail', (
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    debugPrint(
      'settings texts: ${find.byType(Text).evaluate().map((element) => (element.widget as Text).data).whereType<String>().toList()}',
    );

    Future<void> open(String label) async {
      // 设置页是懒加载列表，靠后的分组在首屏根本没被构建出来；
      // 先滚到目标行，再按行点击。
      if (find.text(label).evaluate().isEmpty) {
        await tester.scrollUntilVisible(find.text(label), 240);
        await tester.pumpAndSettle();
      }
      final target = find.text(label).first;
      await Scrollable.ensureVisible(target.evaluate().single, alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      // 选项面板统一走底部玻璃弹层：有把手、大标题、圆形关闭键，
      // 左右留白而不是贴边铺满。
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.byType(KoyzeSheetTitle)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(KoyzeSheetGrabber)),
        findsNothing,
      );
      final panel = tester.getRect(find.byType(GlassSurface).last);
      expect(panel.left, greaterThanOrEqualTo(12));
      expect(panel.right, lessThanOrEqualTo(390 - 12));
      final close = find.descendant(
        of: sheet,
        matching: find.byIcon(Icons.close_rounded),
      );
      expect(close, findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    }

    await open('Audio quality');
    await open('Default search source');
    await open('Language');
    await open('Download quality');
  });

  testWidgets('quality picker keeps the selected option and updates state', (
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 设置项越加越多，播放设置已经不在首屏内；列表是惰性构建的，
    // 不先滚到位连 finder 都找不到它，所以要滚到可见再点。
    final quality = find.text('Audio quality').first;
    await tester.scrollUntilVisible(
      find.text('Audio quality'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(quality);
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('High (320 kbps)')),
      findsOneWidget,
    );
    // 每一行都预置了勾，只有选中项的勾被放大到 1。
    expect(
      find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate(
          (widget) => widget is AnimatedScale && widget.scale == 1,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: sheet, matching: find.text('Lossless (FLAC)')),
    );
    await tester.pumpAndSettle();

    expect(container.read(audioQualityProvider), AudioQualityOption.lossless);
    expect(find.byType(BottomSheet), findsNothing);
  });

  test('settings page routes capture their tile expansion origin', () {
    final source = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();

    for (final route in [
      '/stats',
      '/download',
      '/local-music',
      '/custom-source',
      '/ai-assistant',
      '/ai-settings',
      '/ai-schedules',
      '/subsonic-settings',
      '/equalizer',
      '/sync',
    ]) {
      expect(
        RegExp(
          "context\\.push\\('$route'\\),\\s*captureExpandOrigin: true",
        ).hasMatch(source),
        isTrue,
        reason: '$route must return to its settings tile',
      );
    }

    expect(source, isNot(contains('重复歌曲')));
    expect(source, isNot(contains('/duplicates')));
    // 这两项有更贴切的入口，设置页里不再重复放一份：音源检测在音源卡片上，
    // AI 歌单已并入 AI 助手。AI 设置则随新的「AI」分区回到设置页——入口多一个
    // 不碍事，找不到配置在哪才碍事。
    for (final retired in ['/source-check', '/ai-playlist']) {
      expect(
        source,
        isNot(contains(retired)),
        reason: '$retired should not be reachable from settings',
      );
    }
  });

  test(
    'sync rail entry pushes directly without selecting the settings tab',
    () {
      final source = File(
        'lib/features/home/presentation/independent_side_rail.dart',
      ).readAsStringSync();
      final scaffold = File(
        'lib/features/home/presentation/main_scaffold.dart',
      ).readAsStringSync();

      expect(source, contains("appRouter.push('/sync')"));
      expect(
        scaffold,
        isNot(contains("onTap: () => _open(context, 3, '/sync')")),
      );
    },
  );
  test('every settings row is an entry so search cannot miss one', () {
    final source = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();

    // 页面按 SettingsEntry 渲染，搜索按同一张表建索引。谁要是又在 build 里
    // 手写一行，那一行就会「看得见、搜不到」——这里把它摁住。
    expect(source, contains('List<SettingsSectionSpec> _buildSections('));
    expect(source, isNot(contains('Widget _buildSection(')));
    expect(source, isNot(contains('_buildNavTile(')));
    expect(RegExp(r'return _SettingsNavTile\(').allMatches(source), hasLength(1));
    // 右上角的搜索入口。
    expect(source, contains('s.settingsSearch'));
    expect(source, contains('SettingsSearchLayer('));
  });

  test('default search picker includes self-hosted and nas sources', () {
    final settings = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();
    final search = File(
      'lib/features/search/presentation/search_provider.dart',
    ).readAsStringSync();

    expect(settings, contains('allSearchSourcesProvider'));
    expect(settings, contains('platformPickerDescription'));
    expect(settings, contains('platformPickerIcon'));
    expect(settings, contains("case 'subsonic':"));
    expect(settings, contains("en ? 'NAS library' : 'NAS 乐库'"));
    expect(settings, isNot(contains("case 'emby':")));
    expect(settings, isNot(contains('static const _options')));

    expect(search, contains("SearchSourceItem(id: 'subsonic', name: 'NAS')"));
    expect(search, contains('_searchConnectedNas'));
    expect(search, isNot(contains('kind.shortSearchLabel')));
    expect(search, isNot(contains('if (connected) SearchSourceItem')));
    expect(
      search,
      isNot(contains('if (ref.watch(nasConnectedProvider(kind)))')),
    );
  });
}
