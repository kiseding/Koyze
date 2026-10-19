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

  test('顶部是「大标题 + 分段控件」两行，取代原来的标题栏', () {
    final header = _read('lib/core/widgets/frosted_tab_header.dart');
    final tabs = _read('lib/core/widgets/root_tab_bar.dart');
    final shell = _read('lib/features/home/presentation/main_scaffold.dart');

    // 壳层提供 RootTabScope；标题栏在根壳层里渲染标题 + 分段控件。
    expect(shell, contains('RootTabScope('));
    expect(header, contains('RootTabScope.maybeOf'));
    expect(header, contains('RootTabBar()'));
    // 栏本身仍然不铺满宽度的磨砂底：底留给标题区一层中性渐隐。
    expect(
      header.substring(
        header.indexOf('if (tabs != null)'),
        header.indexOf('Widget _titleBar'),
      ),
      isNot(contains('GradientAppBarBackground')),
    );
    // 四个入口，药丸在四等分之间滑动，不再是一块玻璃胶囊。
    expect(tabs, contains("s.home"));
    expect(tabs, contains("s.charts"));
    expect(tabs, contains("s.playlists"));
    expect(tabs, contains("s.settings"));
    expect(tabs, contains('AnimatedPositioned('));
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
}
