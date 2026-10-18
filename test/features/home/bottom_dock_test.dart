import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/features/home/presentation/widgets/bottom_dock.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';

void main() {
  const screen = Size(390, 844);

  Future<void> pumpDock(
    WidgetTester tester, {
    required void Function(int) onTap,
    int selected = 0,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentMusicProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: KoyzeBottomDock(
                metrics: KoyzeDockMetrics(
                  screen: screen,
                  bottomInset: 0,
                ),
                selectedIndex: selected,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('四个图标 tab 均分，封面居中悬在中间一格', (tester) async {
    var tapped = -1;
    await pumpDock(tester, onTap: (index) => tapped = index);

    expect(find.byIcon(Icons.home), findsOneWidget); // 选中态是实心图标
    expect(find.byIcon(Icons.leaderboard_outlined), findsOneWidget);
    expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // 中间封面尺寸固定、水平居中。
    final disc = find.byType(DockArtworkDisc);
    expect(tester.getSize(disc), const Size(kDockDiscSize, kDockDiscSize));
    expect(tester.getCenter(disc).dx, closeTo(screen.width / 2, 0.5));

    // 玻璃条比封面矮，封面上下各溢出 3dp。
    expect(kDockDiscSize - kDockBarHeight, closeTo(6, 0.001));

    await tester.tap(find.byIcon(Icons.leaderboard_outlined));
    expect(tapped, 1);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    expect(tapped, 3);
  });

  testWidgets('没有歌曲时封面只当占位，不跳播放页', (tester) async {
    await pumpDock(tester, onTap: (_) {});

    final disc = find.byType(DockArtworkDisc);
    expect(disc, findsOneWidget);
    // 封面里有一个轴孔，说明画的是唱片而不是普通圆角封面。
    expect(
      find.descendant(of: disc, matching: find.byIcon(Icons.music_note_rounded)),
      findsOneWidget,
    );
  });

  testWidgets('morph 目标几何与 dock 实际布局一致', (tester) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentMusicProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  height: kDockDiscSize,
                  child: Center(
                    child: KoyzeBottomDock(
                      metrics: KoyzeDockMetrics(
                        screen: screen,
                        bottomInset: 0,
                      ),
                      selectedIndex: 0,
                      onTap: (_) {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final metrics = KoyzeDockMetrics(screen: screen, bottomInset: 0);
    // dock 组件 bottom 偏移 + 高度 —— 播放页收起时用的就是这两个数。
    expect(metrics.dockWidgetBottom, 10);
    final discRect = tester.getRect(find.byType(DockArtworkDisc));
    expect(discRect.center.dx, closeTo(metrics.discRect.center.dx, 0.5));
    expect(discRect.center.dy, closeTo(metrics.discRect.center.dy, 0.5));
    expect(
      metrics.controlsPlayRect.center.dx,
      closeTo(screen.width / 2, 0.001),
    );
    // 控件行底边必须在 dock 顶边之上。
    expect(metrics.controlsBottom, greaterThan(metrics.barTop));
  });
}
