// 歌单列表必须能滚到根 tab 栏和搜索框背后，否则滤镜只能看到纯色页面底。
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/core/theme/effect_policy.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/core/widgets/frosted_tab_header.dart';
import 'package:koyze/core/widgets/glass_backdrop.dart';
import 'package:koyze/core/widgets/koyze_sheet.dart';
import 'package:koyze/core/widgets/origo_chrome.dart';
import 'package:koyze/core/widgets/root_tab_bar.dart';
import 'package:koyze/features/car_mode/presentation/car_mode_provider.dart';
import 'package:koyze/features/home/presentation/main_scaffold.dart';
import 'package:koyze/features/lyric/domain/lyric.dart';
import 'package:koyze/features/lyric/presentation/lyric_provider.dart';
import 'package:koyze/features/player/domain/player_service.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/playlist/presentation/playlist_screen.dart';
import 'package:koyze/features/recommend/domain/recommendation_engine.dart';
import 'package:koyze/features/recommend/presentation/recommendation_provider.dart';
import 'package:koyze/features/settings/presentation/glass_effect_sheet.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 竖屏 iPhone 尺寸，状态栏 59（和 frosted_tab_header_test 同一组数字）。
const _topInset = 59.0;
const _screen = Size(393, 852);
const _frameKey = ValueKey('root-chrome-frame');

class _Repository implements PlaylistRepository {
  _Repository(List<Playlist> playlists)
    : snapshot = PlaylistSnapshot(schemaVersion: 1, playlists: playlists);

  PlaylistSnapshot snapshot;
  @override
  Future<PlaylistSnapshot> load() async => snapshot;
  @override
  Future<void> save(PlaylistSnapshot value) async => snapshot = value;
}

/// 使用实际的根壳层和歌单页。其他 tab 用占位页，避免引入网络和音频服务。
Future<void> _mount(
  WidgetTester tester, {
  List<Playlist> playlists = const [],
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _screen;
  tester.view.padding = const FakeViewPadding(top: _topInset);
  tester.view.viewPadding = const FakeViewPadding(top: _topInset);
  addTearDown(tester.view.reset);

  final container = _container(playlists);
  await container.read(playlistServiceProvider).init();
  final swipe = GlobalKey<SwipeBranchContainerState>();
  final router = GoRouter(
    initialLocation: '/playlist',
    routes: [
      StatefulShellRoute(
        builder: (_, _, shell) => MainScaffold(
          navigationShell: shell,
          onBranchTap: (index) => swipe.currentState!.select(index),
        ),
        navigatorContainerBuilder: (_, shell, children) => SwipeBranchContainer(
          key: swipe,
          currentIndex: shell.currentIndex,
          onSelect: shell.goBranch,
          children: children,
        ),
        branches: [
          for (final path in ['/', '/charts', '/playlist', '/settings'])
            StatefulShellBranch(
              preload: true,
              routes: [
                GoRoute(
                  path: path,
                  builder: (_, _) => path == '/playlist'
                      ? const PlaylistScreen()
                      : const SizedBox.expand(),
                ),
              ],
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _frameKey,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: brightness == Brightness.dark
              ? AppTheme.darkTheme()
              : AppTheme.lightTheme(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(List<Playlist> playlists) {
  final container = ProviderContainer(
    overrides: [
      landscapeShellProvider.overrideWithValue(false),
      playlistRepositoryProvider.overrideWithValue(_Repository(playlists)),
      playerServiceProvider.overrideWithValue(PlayerService()),
      currentMusicProvider.overrideWithValue(null),
      isPlayingProvider.overrideWithValue(const AsyncData(false)),
      currentLyricProvider.overrideWithValue(Lyrics.empty()),
      currentLineIndexProvider.overrideWithValue(-1),
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

List<Playlist> _samplePlaylists() {
  final now = DateTime.utc(2026);
  return List.generate(12, (i) {
    return Playlist(
      id: 'sample-$i',
      name: 'Sample ${i + 1}',
      createdAt: now,
      updatedAt: now,
    );
  });
}

Finder get _tabBackdrop => find.descendant(
  of: find.byType(FrostedTabHeader),
  matching: find.byType(GradientFrost),
);

Finder get _searchSurface => find.ancestor(
  of: find.byType(TextField),
  matching: find.byType(GradientFrost),
);

Finder _filterIn(Finder surface) =>
    find.descendant(of: surface, matching: find.byType(BackdropFilter));

Future<ByteData> _captureFrame(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_frameKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  }))!;
}

double _meanRgbDifference(ByteData before, ByteData after, Rect area) {
  var sum = 0;
  for (var y = area.top.toInt(); y < area.bottom.toInt(); y++) {
    for (var x = area.left.toInt(); x < area.right.toInt(); x++) {
      final offset = (y * _screen.width.toInt() + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        sum +=
            (before.getUint8(offset + channel) -
                    after.getUint8(offset + channel))
                .abs();
      }
    }
  }
  return sum / (area.width * area.height * 3);
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
    GlassScrollActivity.reset();
    rootBranchDragPosition.value = null;
    rootBranchSettle.value = null;
    rootHeaderBranchIndex.value = 0;
    rootBranchIndex.value = 0;
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
      await _mount(tester);

      final viewport = outermostViewport(tester);
      expect(
        viewport.top,
        0,
        reason:
            '滚动视口被压到了 y=${viewport.top}，内容永远到不了标题栏背后，'
            '栏上的磨砂就会看起来「没生效」——这正是它只在设置页可见的原因',
      );
    });

    testWidgets('列表铺满屏幕，不是 0×0 那种空白页', (tester) async {
      await _mount(tester);

      // Stack 默认 `StackFit.loose`，尺寸只由**非定位子项**撑开。把唯一的
      // 撑尺寸子项（列表）包进 Positioned.fill，而另一个子项
      // RootHeaderPublisher 返回 SizedBox.shrink()，整个 Stack 就会塌成
      // 0×0——这一页看起来一片空白，但 analyze 和「视口在 y=0」全过。
      final list = tester.getRect(find.byType(ListView));
      expect(list.width, greaterThan(0), reason: '列表宽度是 0，页面被 Stack 的尺寸规则挤塌了');
      expect(list.height, greaterThan(0), reason: '列表高度是 0，页面被 Stack 的尺寸规则挤塌了');
      expect(list.size, _screen);
    });

    testWidgets('列表留白里含标题栏高度，首项不会被栏盖住', (tester) async {
      await _mount(tester);

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
      await _mount(tester);

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

  for (final brightness in Brightness.values) {
    testWidgets('滚到背后的歌单在两块玻璃上随滑杆变化（$brightness）', (tester) async {
      GlassEffectConfig.setSurfaceOpacity(0.35);
      GlassEffectConfig.setSurfaceBlur(0);
      await _mount(
        tester,
        playlists: _samplePlaylists(),
        brightness: brightness,
      );

      final searchRect = tester.getRect(_searchSurface);
      final tabRect = tester.getRect(_tabBackdrop);
      final areas = {
        'tab 栏状态区': const Rect.fromLTRB(24, 8, 140, _topInset - 6),
        // 导航行下缘的留白，避开会自行变色的胶囊。
        'tab 栏导航区': Rect.fromLTRB(
          24,
          tabRect.bottom - 7,
          140,
          tabRect.bottom - 1,
        ),
        '歌单搜索框': Rect.fromLTRB(
          searchRect.left + 12,
          searchRect.top + 4,
          searchRect.left + 128,
          searchRect.bottom - 4,
        ),
      };
      final firstClear = await _captureFrame(tester);
      GlassEffectConfig.setSurfaceOpacity(0.9);
      await tester.pump();
      final firstDenser = await _captureFrame(tester);

      GlassEffectConfig.setSurfaceOpacity(0.35);
      final scroll = Scrollable.of(
        tester.element(find.byType(Viewport)),
      ).position;
      expect(scroll.maxScrollExtent, greaterThan(195));
      // 让彩色入口分别经过导航栏和搜索框，固定位置以便比较像素。
      scroll.jumpTo(195);
      await tester.pumpAndSettle();
      final clear = await _captureFrame(tester);
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pump();
      final blurred = await _captureFrame(tester);

      final listFilter = _filterIn(find.byType(ListView)).first;
      final groupKey = tester
          .element(listFilter)
          .getInheritedWidgetOfExactType<BackdropGroup>()!
          .backdropKey;
      expect(
        tester.renderObject<RenderBackdropFilter>(listFilter).backdropKey,
        same(groupKey),
      );
      for (final surface in [_tabBackdrop, _searchSurface]) {
        final filter = _filterIn(surface);
        expect(filter, findsOneWidget);
        expect(
          tester
              .element(filter)
              .getInheritedWidgetOfExactType<BackdropGroup>()
              ?.backdropKey,
          same(groupKey),
        );
        expect(
          tester.renderObject<RenderBackdropFilter>(filter).backdropKey,
          isNull,
        );
      }

      GlassEffectConfig.setSurfaceOpacity(0.9);
      await tester.pump();
      final denser = await _captureFrame(tester);

      for (final MapEntry(key: label, value: area) in areas.entries) {
        expect(
          _meanRgbDifference(firstClear, firstDenser, area),
          greaterThan(0.8),
          reason: '列表未滚动时，$label 也应随不透明度滑杆变化',
        );
        expect(
          _meanRgbDifference(clear, blurred, area),
          greaterThan(0.8),
          reason: '$label 的背景应随虚化滑杆变化',
        );
        expect(
          _meanRgbDifference(blurred, denser, area),
          greaterThan(0.8),
          reason: '$label 的背景应随不透明度滑杆变化',
        );
      }
      expect(tester.getRect(_searchSurface), searchRect);
      GlassEffectConfig.setSurfaceBlur(0);
      await tester.pump();
      expect(_filterIn(_tabBackdrop), findsNothing);
      expect(_filterIn(_searchSurface), findsNothing);
    });
  }

  testWidgets('调过界面质感后仍能搜索、滚动和切换 tab', (tester) async {
    await _mount(tester, playlists: _samplePlaylists());
    final field = find.byType(TextField);
    final context = tester.element(field);
    final strings = S.of(context);
    unawaited(showGlassEffectSheet(context));
    await tester.pumpAndSettle();

    final sheet = find.byType(GlassEffectSheet);
    final sliders = find.descendant(of: sheet, matching: find.byType(Slider));
    expect(sliders, findsNWidgets(2));
    final opacitySlider = tester.getRect(sliders.first);
    await tester.tapAt(
      opacitySlider.centerLeft + Offset(opacitySlider.width / 4, 0),
    );
    await tester.tap(sliders.last);
    await tester.pumpAndSettle();
    expect(
      GlassEffectConfig.surfaceOpacity,
      lessThan(GlassEffectConfig.defaultSurfaceOpacity),
    );
    expect(GlassEffectConfig.surfaceBlur, 0.5);
    await tester.tap(
      find.descendant(of: sheet, matching: find.byType(KoyzeSheetClose)),
    );
    await tester.pumpAndSettle();

    for (final surface in [_tabBackdrop, _searchSurface]) {
      final frost = tester.widget<GradientFrost>(surface);
      final backdrop = tester.widget<GlassBackdrop>(
        find.descendant(of: surface, matching: find.byType(GlassBackdrop)),
      );
      expect(backdrop.sigma, closeTo(frost.sigma * 0.5, 0.001));
    }

    await tester.tap(field);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(field, 'Sample 7');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('Sample 7'),
      ),
      findsOneWidget,
    );
    expect(find.text('Sample 1'), findsNothing);

    await tester.tap(find.byTooltip(strings.clearSearch));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('Sample 1'), findsOneWidget);

    final searchRect = tester.getRect(_searchSurface);
    final scroll = Scrollable.of(
      tester.element(find.byType(Viewport)),
    ).position;
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -40));
    await gesture.moveBy(const Offset(0, -195));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scroll.pixels, greaterThan(0));
    expect(tester.getRect(_searchSurface), searchRect);

    await tester.tap(find.byKey(const ValueKey('root-tab-1')));
    await tester.pumpAndSettle();
    expect(rootBranchIndex.value, 1);
    expect(field, findsNothing);

    await tester.dragFrom(const Offset(250, 400), const Offset(-165, 0));
    await tester.pumpAndSettle();
    expect(rootBranchIndex.value, 2);
    expect(field, findsOneWidget);
    expect(_filterIn(_searchSurface), findsOneWidget);
  });
}
