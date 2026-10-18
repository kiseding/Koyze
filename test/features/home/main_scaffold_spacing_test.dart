import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bottom chrome is the GZ-style dock plus a floating control row', () {
    final source = File(
      'lib/features/home/presentation/main_scaffold.dart',
    ).readAsStringSync();

    expect(source, contains('KoyzeDockMetrics'));
    expect(source, contains('KoyzeBottomDock'));
    expect(source, contains('MiniPlayerControls'));
    // 内容底部让位由 dock 几何统一给出，避免三处手算漂移。
    expect(source, contains('dock.contentObstruction'));
    expect(source, contains('dock.dockWidgetBottom'));
    expect(source, isNot(contains('_BottomNav')));
    expect(source, isNot(contains('GlassSurface(')));
    expect(source, isNot(contains('AppGlassStyle.bar')));
  });

  test('dock keeps the artwork in the middle cell and opens the player', () {
    final dock = File(
      'lib/features/home/presentation/widgets/bottom_dock.dart',
    ).readAsStringSync();

    expect(dock, contains('const double kDockBarHeight'));
    expect(dock, contains('const double kDockDiscSize'));
    // 五格等宽：中间一格留白给封面。
    expect(dock, contains('const Expanded(child: SizedBox.expand())'));
    expect(dock, contains('const DockArtworkDisc()'));
    // 点封面仍是进全屏播放器。
    expect(dock, contains('pushPlayerRoute(context, hasSong: true)'));
    // 条身是液态玻璃，不是磨砂卡片：液玻璃才有"透出底部元素"的效果。
    expect(dock, contains('LiquidGlassSurface('));
    expect(dock, isNot(contains('OrigoChromeSurface(')));
  });

  test('页面一直画到屏幕底边，滚动内容从 dock 后面经过', () {
    final source = File(
      'lib/features/home/presentation/main_scaffold.dart',
    ).readAsStringSync();

    // 底部让位只能通过 RootShellLayout.obscuredBottom 告诉滚动列表，
    // 不能把整个导航区从底边裁掉——裁掉之后玻璃后面就是空的。
    expect(source, contains('obscuredBottom: chromeBottom'));
    expect(source, isNot(contains('bottom: chromeBottom')));
    expect(source, isNot(contains('bottom: usesSideNavigation')));
  });

  test('control row has no surface behind it', () {
    final mini = File(
      'lib/features/player/presentation/widgets/mini_player.dart',
    ).readAsStringSync();
    final controls = mini.substring(
      mini.indexOf('class MiniPlayerControls'),
      mini.indexOf('class MiniPlayer extends'),
    );

    expect(controls, contains('MainAxisAlignment.center'));
    expect(controls, isNot(contains('OrigoChromeSurface')));
    expect(controls, isNot(contains('GlassSurface')));
  });
}
