// 榜单设置弹窗的行为。
//
// 钉三件事：
//   1. 弹窗按平台分页，进弹窗只铺第一个平台的榜；
//   2. 点平台标签只切换那一个平台的内容；
//   3. 关掉某个榜 / 整个平台，布局 provider 里的 hidden 标记跟着变。
//
// 分类与布局都用固定数据覆写，不依赖网络与磁盘。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/music_source/platform/music_platform.dart';
import 'package:koyze/core/widgets/fx_switch.dart';
import 'package:koyze/features/leaderboard/presentation/leaderboard_provider.dart';
import 'package:koyze/features/leaderboard/presentation/leaderboard_settings_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StaticCategories extends LeaderboardCategoriesNotifier {
  _StaticCategories(this.categories);

  final List<LeaderboardCategory> categories;

  @override
  AsyncValue<List<LeaderboardCategory>> build() => AsyncValue.data(categories);
}

class _StaticLayout extends LeaderboardLayoutNotifier {
  @override
  List<LeaderboardLayoutItem> build() => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const categories = <LeaderboardCategory>[
    LeaderboardCategory(id: 'tx:1', name: '热歌榜', platform: 'tx'),
    LeaderboardCategory(id: 'tx:2', name: '新歌榜', platform: 'tx'),
    LeaderboardCategory(id: 'kw:1', name: '酷我飙升榜', platform: 'kw'),
  ];

  Future<ProviderContainer> pumpSheet(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        leaderboardCategoriesProvider.overrideWith(
          () => _StaticCategories(categories),
        ),
        leaderboardLayoutProvider.overrideWith(_StaticLayout.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(height: 540, child: LeaderboardSettingsSheet()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('手机宽度下标题行与平台卡不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpSheet(tester);

    // RenderFlex overflow 会被测试框架记成异常；这里显式收一次。
    expect(tester.takeException(), isNull);
  });

  testWidgets('进弹窗只显示第一个平台的榜单', (tester) async {
    await pumpSheet(tester);

    // 平台名在标签和平台卡上各出现一次。
    expect(find.text('QQ音乐'), findsNWidgets(2));
    expect(find.text('酷我音乐'), findsOneWidget);
    expect(find.text('热歌榜'), findsOneWidget);
    expect(find.text('新歌榜'), findsOneWidget);
    expect(find.text('酷我飙升榜'), findsNothing);
  });

  testWidgets('点平台标签切换该平台的榜单', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('酷我音乐'));
    await tester.pumpAndSettle();

    expect(find.text('酷我飙升榜'), findsOneWidget);
    expect(find.text('热歌榜'), findsNothing);
    expect(find.text('酷我音乐'), findsNWidgets(2));
  });

  testWidgets('点榜单行把 hidden 写回布局', (tester) async {
    final container = await pumpSheet(tester);

    await tester.tap(find.text('新歌榜'));
    await tester.pumpAndSettle();

    final layout = container.read(leaderboardLayoutProvider);
    final item = layout.firstWhere((entry) => entry.key == 'category:tx:2');
    expect(item.hidden, isTrue);
    // 另一个榜不受影响。
    expect(
      layout.firstWhere((entry) => entry.key == 'category:tx:1').hidden,
      isFalse,
    );
  });

  testWidgets('关掉平台会连同其下所有榜单一起隐藏', (tester) async {
    final container = await pumpSheet(tester);

    await tester.tap(find.byType(FxSwitch));
    await tester.pumpAndSettle();

    final layout = container.read(leaderboardLayoutProvider);
    final hidden = {
      for (final item in layout)
        if (item.hidden) item.key,
    };
    expect(hidden, contains('platform:tx'));
    expect(hidden, contains('category:tx:1'));
    expect(hidden, contains('category:tx:2'));
    // 其他平台不受影响。
    expect(hidden, isNot(contains('platform:kw')));
  });
}
