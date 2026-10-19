import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('竖屏只有一条底部迷你播放条，没有 dock、没有独立控件行', () {
    final source = _read('lib/features/home/presentation/main_scaffold.dart');

    expect(source, contains('KoyzeMiniBarMetrics'));
    expect(source, contains('MiniPlayer('));
    // 内容底部让位由迷你栏几何统一给出，避免三处手算漂移。
    expect(source, contains('miniBar.contentObstruction'));
    expect(source, contains('kMiniBarSideMargin'));
    // 旧的唱片 dock 与它上面那排悬浮按钮都已移除。
    expect(source, isNot(contains('KoyzeBottomDock')));
    expect(source, isNot(contains('DockArtworkDisc')));
    expect(source, isNot(contains('MiniPlayerControls')));
    expect(source, isNot(contains('_BottomNav')));
  });

  test('顶部只有一条 tab 行，导航占据原来标题的位置', () {
    final header = _read('lib/core/widgets/frosted_tab_header.dart');
    final tabs = _read('lib/core/widgets/root_tab_bar.dart');
    final shell = _read('lib/features/home/presentation/main_scaffold.dart');

    // 壳层提供 RootTabScope；标题栏在根壳层里渲染 tab 行。
    expect(shell, contains('RootTabScope('));
    expect(header, contains('RootTabScope.maybeOf'));
    expect(header, contains('RootTabBar()'));
    // 栏本身仍然不铺满宽度的磨砂底：底留给导航行一层中性渐隐。
    final navBranch = header.substring(
      header.indexOf('if (tabs != null)'),
      header.indexOf('Widget _titleBar'),
    );
    expect(navBranch, isNot(contains('GradientAppBarBackground')));
    // 大标题不再出现在这一支里：选中的 tab 展开后就是页面名，
    // 再画一次 26 号标题只是重复。
    expect(navBranch, isNot(contains('fontSize: 26')));
    // 动作按钮和 tab 同排，靠右。
    expect(navBranch, contains('actions.isNotEmpty'));
    // 四个入口：收起只留图标，选中项向右展开成胶囊。
    expect(tabs, contains('s.home'));
    expect(tabs, contains('s.charts'));
    expect(tabs, contains('s.playlists'));
    expect(tabs, contains('s.settings'));
    expect(tabs, contains('MotionCurve.emphasize'));
    expect(tabs, isNot(contains('LiquidGlassSurface(')));
  });

  test('迷你栏几何与 MiniPlayer 的真实布局一致（morph 起落点）', () {
    final mini = _read('lib/features/player/presentation/widgets/mini_player.dart');
    final bar = _read('lib/features/home/presentation/widgets/mini_bar.dart');

    // 66 高、左右各 12 边距、内部左 8 / 右 7 内边距、封面 50、控件区 180。
    expect(mini, contains('height: widget.floating ? 78 : 66'));
    expect(mini, contains('fromLTRB(widget.floating ? 10 : 8, 7, 7, 7)'));
    expect(mini, contains('widget.floating ? 62 : 50'));
    expect(mini, contains('widget.floating ? 164 : 180'));
    expect(bar, contains('kMiniBarHeight = 66'));
    expect(bar, contains('kMiniBarSideMargin = 12'));
    expect(bar, contains('kMiniBarArtworkSize = 50'));
    expect(bar, contains('kMiniBarControlsWidth = 180'));
  });

  test('页面一直画到屏幕底边，滚动内容从迷你栏后面经过', () {
    final source = _read('lib/features/home/presentation/main_scaffold.dart');

    // 底部让位只能通过 RootShellLayout.obscuredBottom 告诉滚动列表，
    // 不能把整个导航区从底边裁掉——裁掉之后玻璃后面就是空的。
    expect(source, contains('obscuredBottom: chromeBottom'));
    expect(source, isNot(contains('bottom: chromeBottom')));
  });

  test('顶部栏只在壳层渲染一次，四个根页面只发布标题', () {
    final shell = _read('lib/features/home/presentation/main_scaffold.dart');

    // 壳层读控制器里的当前页标题，栏本身画在 SwipeBranchContainer 之外。
    expect(shell, contains('rootHeaderController.headerFor('));
    expect(shell, contains('if (!usesSideNavigation)'));
    expect(shell, contains('FrostedTabHeader('));

    const pages = [
      'lib/features/home/presentation/home_screen.dart',
      'lib/features/leaderboard/presentation/leaderboard_screen.dart',
      'lib/features/playlist/presentation/playlist_screen.dart',
      'lib/features/settings/presentation/settings_screen.dart',
    ];
    for (final page in pages) {
      final source = _read(page);
      // 栏一旦留在页面子树里，切 tab 时就会跟着页面横移。
      expect(source, isNot(contains('FrostedTabHeader(')), reason: page);
      expect(source, contains('RootHeaderPublisher('), reason: page);
    }
  });

  test('点击 tab 瞬时切换，横移只留给手势', () {
    final router = _read('lib/router/app_router.dart');
    final tap = router.substring(
      router.indexOf('onBranchTap:'),
      router.indexOf('navigatorContainerBuilder'),
    );

    // 栏不跟着页面走，页面再慢慢滑 280ms 就和栏脱节了：点击同帧换，
    // 只有药丸滑过去。拖拽切页仍然走 SwipeBranchContainer 的跟手动画。
    expect(tap, contains('goBranch(index)'));
    expect(tap, isNot(contains('state.select(')));
  });
}
