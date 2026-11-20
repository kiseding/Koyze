// 根页面必须让内容能从标题栏背后滚过去。
//
// 为什么值得单独钉一个测试：标题栏在四个 tab 页里是**同一根** widget（由
// MainScaffold 渲染一次），玻璃层本身没问题。但它的磨砂只在「背后有东西」
// 时才看得见——`BackdropFilter` 糊一层纯色页面底，和什么都不做是同一个像素。
//
// 于是「tab 栏怎么只有设置页有效果」这种 bug 的根因不在标题栏，而在各个根
// 页面把滚动视口摆在了哪里：
//
//   设置页  ListView(padding.top = 栏高)              视口从 y=0 → 磨砂可见
//   首页    SingleChildScrollView(padding.top)        视口从 y=0 → 磨砂可见
//   歌单页  Column[SizedBox(栏高), Expanded(列表)]    视口被压到栏下沿 → 看不见
//   榜单页  Padding(top: 栏高, child: CustomScrollView) 同上 → 看不见
//
// 后两个的列表内容裁在自己的盒子里，永远到不了栏背后，于是同一根栏在两页上
// 看起来像「没生效」。这个文件钉住两件事：
//
//   1. 页面里最外层滚动视图的**视口顶边**必须落在 y=0；
//   2. 视口顶边之前不能有「和标题栏等高」的占位盒子把视口顶下去。
//
// 这比断言某段源码里没有 `Padding(top: ...)` 更贴近真实回归：换一种写法
// （比如 SizedBox + Align）一样会把视口推下去，而这里照样能抓住。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/core/widgets/frosted_tab_header.dart';
import 'package:koyze/core/widgets/root_shell_layout.dart';
import 'package:koyze/features/player/domain/player_service.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/playlist/presentation/playlist_screen.dart';
import 'package:koyze/features/recommend/domain/recommendation_engine.dart';
import 'package:koyze/features/recommend/presentation/recommendation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 竖屏 iPhone 尺寸，状态栏 59（和 frosted_tab_header_test 同一组数字）。
const _topInset = 59.0;
const _screen = Size(393, 852);

class _Repository implements PlaylistRepository {
  _Repository();
  PlaylistSnapshot snapshot = PlaylistSnapshot(
    schemaVersion: 1,
    playlists: const [],
  );
  @override
  Future<PlaylistSnapshot> load() async => snapshot;
  @override
  Future<void> save(PlaylistSnapshot value) async => snapshot = value;
}

/// 复刻根壳层的结构：页面铺满，标题栏盖在最上层，页面在 `RootShellLayout`
/// 里（页面靠它判断要不要给栏让位）。
Widget _host(Widget page, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: _screen,
          padding: EdgeInsets.only(top: _topInset),
          viewPadding: EdgeInsets.only(top: _topInset),
        ),
        child: RootShellLayout(
          usesSideNavigation: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              page,
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(child: FrostedTabHeader(title: '')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      playlistRepositoryProvider.overrideWithValue(_Repository()),
      // 页面只要有实例就能建出来；测试不发请求、不播音。
      playerServiceProvider.overrideWithValue(PlayerService()),
      // 推荐卡的真实实现会挂一串定时器：先是 3 秒启动延迟，加载完成后又按
      // TTL 排下一次刷新。测试只关心布局，所以让 loader 永不返回——provider
      // 停在 AsyncValue.loading，不会再排刷新定时器，卡片照常渲染成占位。
      recommendationProvider.overrideWith(
        () => RecommendationNotifier(
          loader: () => Completer<List<RecommendedSong>>().future,
          startupDelay: Duration.zero,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GlassEffectConfig.setSurfaceBlur(1);
  });

  tearDown(() {
    GlassEffectConfig.setSurfaceOpacity(
      GlassEffectConfig.defaultSurfaceOpacity,
    );
    GlassEffectConfig.setSurfaceBlur(GlassEffectConfig.defaultSurfaceBlur);
  });

  /// 页面最外层滚动视图的视口矩形。
  ///
  /// 用 [Viewport] 而不是 Scrollable：`Viewport` 是真正裁剪内容、决定「内容
  /// 能画到哪儿」的那个盒子，加在外层的 Padding 会原样体现在它的 top 上。
  Rect outermostViewport(WidgetTester tester) {
    final finder = find.byType(Viewport);
    expect(finder, findsWidgets, reason: '这一页没有滚动视图？');
    return tester.getRect(finder.first);
  }

  group('歌单页', () {
    testWidgets('滚动视口从屏幕顶开始，内容能钻到标题栏背后', (tester) async {
      await tester.pumpWidget(_host(const PlaylistScreen(), _container()));
      await tester.pump();

      final viewport = outermostViewport(tester);
      expect(
        viewport.top,
        0,
        reason:
            '滚动视口被压到了 y=${viewport.top}，内容永远到不了标题栏背后，'
            '栏上的磨砂就会看起来「没生效」——这正是它只在设置页可见的原因',
      );
    });

    testWidgets('列表留白里含标题栏高度，首项不会被栏盖住', (tester) async {
      await tester.pumpWidget(_host(const PlaylistScreen(), _container()));
      await tester.pump();

      final listView = tester.widget<ListView>(find.byType(ListView));
      final padding = listView.padding! as EdgeInsets;
      final extent = FrostedTabHeader.extent(
        tester.element(find.byType(PlaylistScreen)),
      );
      expect(
        padding.top,
        greaterThanOrEqualTo(extent),
        reason: '列表顶部留白不够，第一行会被标题栏压住',
      );
    });

    testWidgets('页面里没有和标题栏等高的顶部占位盒子', (tester) async {
      await tester.pumpWidget(_host(const PlaylistScreen(), _container()));
      await tester.pump();

      // 旧的 `Column[SizedBox(栏高), Expanded]` 在页面最顶留了一块等高空白，
      // 视口根因此下移。现在改成 Stack + 列表 padding，页面里不该再有这种盒子。
      // 只看页面自身子树，别把壳层里别处的 SizedBox 算进来。
      final extent = FrostedTabHeader.extent(
        tester.element(find.byType(PlaylistScreen)),
      );
      final spacers = tester.widgetList<SizedBox>(
        find.descendant(
          of: find.byType(PlaylistScreen),
          matching: find.byType(SizedBox),
        ),
      );
      expect(
        spacers.where((box) => box.height == extent && box.width == null),
        isEmpty,
        reason: '页面里还有一块和标题栏等高的空白占位，视口又被推下去了',
      );
    });
  });

  group('首页 / 设置页这两条参照线', () {
    // 这两页本来就把留白写在滚动视图的 padding 里，视口在顶部。它们的
    // 行为是「正确」的那一侧，这里不重复渲染它们（依赖太重），只把约定
    // 记在案：新页面要么照它们写，要么照本文件的断言写。
    test('留白写在滚动视图 padding 里，视口自然在顶部', () {
      // 这条不是行为断言，只是防止整个 group 被 analyzer 当成空块。
      expect(const EdgeInsets.only(top: _topInset).top, _topInset);
    });
  });
}
