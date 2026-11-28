// 榜单页平台胶囊的端到端行为。
//
// 为什么不能只做源码字符串断言：胶囊有几颗、进页面停在哪个平台、切平台
// 之后还剩几段、滚动时胶囊会不会跟着跑掉，这些都只有真渲染一次才看得见。
// 本文件钉五件事：
//   1. 胶囊只有四个平台，没有「全部」；
//   2. 进页面就停在第一个平台，四个平台不会一起铺开；
//   3. 点另一颗胶囊只换那一个平台的内容；
//   4. 胶囊吸顶，滚到底也还在（随时能切）；
//   5. 选中那颗是品牌色的玻璃面：浓度跟着「界面不透明度」，未选中的没有底。
//
// 数据来源是各平台内置的静态榜单（tx_source.dart 等），不发网络请求，所以
// 结果与网络无关。
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/core/theme/platform_colors.dart';
import 'package:koyze/core/widgets/gradient_bar_backgrounds.dart';
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

  tearDown(() {
    GlassEffectConfig.setSurfaceOpacity(
      GlassEffectConfig.defaultSurfaceOpacity,
    );
    GlassEffectConfig.setSurfaceBlur(GlassEffectConfig.defaultSurfaceBlur);
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

    // 分组标题已经去掉，每个平台名只在胶囊里出现一次。
    expect(find.text('QQ音乐'), findsOneWidget);
    expect(find.text('酷我音乐'), findsOneWidget);
    expect(find.text('网易云'), findsOneWidget);
    expect(find.text('酷狗音乐'), findsOneWidget);
  });

  testWidgets('进页面只显示第一个平台的榜单', (tester) async {
    await pumpLeaderboard(tester);

    expect(find.text('热歌榜'), findsWidgets);
    expect(find.text('酷我音乐'), findsOneWidget);

    // 「N 个榜单」那两处重复信息已经去掉，数量只留在胶囊的上标里。
    final duplicated = tester
        .widgetList<Text>(find.byType(Text))
        .where((text) => (text.data ?? '').endsWith('个榜单'));
    expect(duplicated, isEmpty);
  });

  testWidgets('数量写进各自的胶囊', (tester) async {
    await pumpLeaderboard(tester);

    for (final platform in ['tx', 'kw', 'wy', 'kg']) {
      final pill = find.byKey(ValueKey('platform-tab-$platform'));
      expect(pill, findsOneWidget, reason: '$platform 少了胶囊');
      expect(
        find.descendant(
          of: pill,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.style?.fontWeight == FontWeight.w800 &&
                int.tryParse(widget.data ?? '') != null,
          ),
        ),
        findsOneWidget,
        reason: '$platform 的胶囊里没有榜单数量',
      );
    }
  });

  testWidgets('点另一颗胶囊只换那一个平台', (tester) async {
    await pumpLeaderboard(tester);

    await tester.tap(find.text('酷我音乐'));
    await tester.pumpAndSettle();

    // 酷我独有的榜出现了，说明真的换了内容而不是只换了高亮。
    expect(find.text('抖音热歌榜'), findsWidgets);
    expect(find.text('QQ音乐'), findsOneWidget);
  });

  testWidgets('滚动时胶囊吸顶，位置不变', (tester) async {
    await pumpLeaderboard(tester);

    final before = tester.getTopLeft(find.text('QQ音乐'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('QQ音乐'), findsOneWidget, reason: '胶囊被滚走了');
    expect(
      tester.getTopLeft(find.text('QQ音乐')).dy,
      closeTo(before.dy, 0.5),
      reason: '胶囊应钉在标题栏下方不动',
    );
  });

  testWidgets('胶囊条使用 tab 栏同款玻璃背景，未选中胶囊透明但保留边缘', (tester) async {
    await pumpLeaderboard(tester);

    Color? tintOf(String platform) {
      final fills = tester.widgetList<ColoredBox>(
        find.descendant(
          of: find.byKey(ValueKey('platform-tab-$platform')),
          matching: find.byType(ColoredBox),
        ),
      );
      return fills.isEmpty ? null : fills.first.color;
    }

    final expected = platformBrandFill(
      'tx',
    ).withValues(alpha: GlassEffectConfig.surfaceAlpha);
    expect(tintOf('tx'), expected, reason: '染色浓度必须等于设置里的不透明度');
    for (final other in ['kw', 'wy', 'kg']) {
      final pill = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(ValueKey('platform-tab-$other')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(tintOf(other), isNull, reason: '$other 未选中却有底色');
      expect(pill.decoration, isA<BoxDecoration>());
      expect(
        (pill.decoration as BoxDecoration).border,
        isNotNull,
        reason: '$other 未选中时缺少边缘',
      );
    }

    final headerFinder = find.descendant(
      of: find.byType(SliverPersistentHeader),
      matching: find.byType(GradientAppBarBackground),
    );
    expect(headerFinder, findsOneWidget, reason: '吸顶胶囊条应使用与顶部 tab 栏相同的磨砂背景');
    final header = tester.widget<GradientAppBarBackground>(headerFinder);
    expect(header.background, isNotNull);
    expect(header.liquidBottomEdge, isFalse, reason: '筛选条不能再画第二条液态底缘');
  });

  testWidgets('调低不透明度，胶囊跟着变淡', (tester) async {
    // 默认不透明度是 0，先把这一档拉满，再验证调低时胶囊确实跟着变淡。
    GlassEffectConfig.setSurfaceOpacity(1);
    addTearDown(
      () => GlassEffectConfig.setSurfaceOpacity(
        GlassEffectConfig.defaultSurfaceOpacity,
      ),
    );
    await pumpLeaderboard(tester);

    Color? tint() {
      final fills = tester.widgetList<ColoredBox>(
        find.descendant(
          of: find.byKey(const ValueKey('platform-tab-tx')),
          matching: find.byType(ColoredBox),
        ),
      );
      return fills.isEmpty ? null : fills.first.color;
    }

    final before = tint()!;
    expect(before.a, closeTo(1, 1e-9));
    GlassEffectConfig.setSurfaceOpacity(GlassEffectConfig.minSurfaceOpacity);
    await tester.pumpAndSettle();

    final after = tint()!;
    expect(after.a, lessThan(before.a));
    expect(after.a, closeTo(GlassEffectConfig.minSurfaceOpacity, 1e-9));
  });

  testWidgets('横屏也默认只显示一个平台', (tester) async {
    await pumpLeaderboard(
      tester,
      size: const Size(2340, 1080),
      sideNavigation: true,
    );

    expect(find.text('全部'), findsNothing);
    // 横屏走的是三列；只选中一个平台时三列只剩一列，所以另外三个平台
    // 只该在胶囊里出现一次。选中的那一家会多出一份列头——列头标的是
    // 「这一列是哪个平台的榜」，和胶囊不是同一件事，横屏下该留着。
    expect(find.text('QQ音乐'), findsNWidgets(2));
    expect(find.text('酷我音乐'), findsOneWidget);
    expect(find.text('网易云'), findsOneWidget);
    expect(find.text('酷狗音乐'), findsOneWidget);
  });
}
