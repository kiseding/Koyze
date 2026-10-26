// 榜单页平台胶囊的端到端行为。
//
// 为什么不能只做源码字符串断言：胶囊有几颗、进页面停在哪个平台、切平台
// 之后还剩几段，这些都只有真渲染一次才看得见。本文件钉三件事：
//   1. 胶囊只有四个平台，没有「全部」；
//   2. 进页面就停在第一个平台，四个平台不会一起铺开；
//   3. 点另一颗胶囊只换那一个平台的内容，剩下的平台不会跟着冒出来。
//
// 数据来源是各平台内置的静态榜单（tx_source.dart 等），不发网络请求，所以
// 结果与网络无关。
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/root_shell_layout.dart';
import 'package:koyze/features/leaderboard/presentation/leaderboard_provider.dart';
import 'package:koyze/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:koyze/features/player/domain/player_service.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 布局与分类缓存都从空开始，让页面走 ensureDefaultLayout 的默认路径。
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLeaderboard(
    WidgetTester tester, {
    Size size = const Size(1080, 2340),
    bool sideNavigation = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 榜单行会按需拉详情，这里全部给空，避免测试里发请求。
          leaderboardSongsProvider.overrideWith((ref, id) async => const []),
          // audioHandler 是 late 全局，测试里没有初始化。换掉这两个
          // provider，「正在播放」高亮就走空状态。
          playerServiceProvider.overrideWithValue(PlayerService()),
          currentMediaItemProvider.overrideWith(
            (ref) => Stream<MediaItem?>.value(null),
          ),
        ],
        // 横屏/桌面走的是左栏 + 三列，这一页靠 RootShellLayout 判断，
        // 不包这层的话宽阔尺寸也只会落到竖屏单列。
        child: RootShellLayout(
          usesSideNavigation: sideNavigation,
          child: const MaterialApp(
            // 语言配置照抄 lib/app.dart：不挂 delegate 的话 MaterialApp
            // 只认 en，断言就得写成英文平台名，和产品实际文案对不上。
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LeaderboardScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('胶囊只有四个平台，没有「全部」', (tester) async {
    await pumpLeaderboard(tester);

    expect(find.text('全部'), findsNothing);
    expect(find.text('All'), findsNothing);

    // 选中的平台同时出现在胶囊和分组标题里，所以是 2；没被选中的平台
    // 只有胶囊这一处，是 1。
    expect(find.text('QQ音乐'), findsNWidgets(2));
    expect(find.text('酷我音乐'), findsOneWidget);
    expect(find.text('网易云'), findsOneWidget);
    expect(find.text('酷狗音乐'), findsOneWidget);
  });

  testWidgets('进页面只显示第一个平台的榜单', (tester) async {
    await pumpLeaderboard(tester);

    // QQ 音乐的第一张主卡在；酷我的主卡不能同时在——两边都有「热歌榜」，
    // 所以按分组标题判断：酷我只出现一次说明它那一段没被渲染。
    expect(find.text('热歌榜'), findsWidgets);
    expect(find.text('酷我音乐'), findsOneWidget);

    // 摘要（顶部）与分组标题（列表里）数的是同一段，两处数字必须一致。
    // 摘要若吃全部分段，会写着四个平台的榜单总数，下面却只列一个平台。
    final counts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .where((data) => data.endsWith('个榜单'))
        .toList();
    expect(counts.length, 2, reason: '摘要 + 分组标题各一处');
    expect(counts.first, counts.last);
  });

  testWidgets('点另一颗胶囊只换那一个平台', (tester) async {
    await pumpLeaderboard(tester);

    await tester.tap(find.text('酷我音乐'));
    await tester.pumpAndSettle();

    // 换过来之后酷我变成「胶囊 + 分组标题」，QQ 只剩胶囊。
    expect(find.text('酷我音乐'), findsNWidgets(2));
    expect(find.text('QQ音乐'), findsOneWidget);
    // 酷我独有的榜出现了，说明真的换了内容而不是只换了高亮。
    expect(find.text('抖音热歌榜'), findsWidgets);
  });

  testWidgets('横屏也默认只显示一个平台', (tester) async {
    await pumpLeaderboard(
      tester,
      size: const Size(2340, 1080),
      sideNavigation: true,
    );

    expect(find.text('全部'), findsNothing);
    // 横屏走的是三列；只选中一个平台时三列只剩一列，所以另外三个平台
    // 只该在胶囊里出现一次，不能再多出一份列头。
    expect(find.text('QQ音乐'), findsNWidgets(2));
    expect(find.text('酷我音乐'), findsOneWidget);
    expect(find.text('网易云'), findsOneWidget);
    expect(find.text('酷狗音乐'), findsOneWidget);
  });
}
