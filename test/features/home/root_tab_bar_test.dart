import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/core/widgets/liquid_glass.dart';
import 'package:koyze/core/widgets/root_tab_bar.dart';

void main() {
  const screen = Size(390, 844);

  Future<void> pumpBar(
    WidgetTester tester, {
    required void Function(int) onTap,
    int selected = 0,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: RootTabScope(
                selectedIndex: selected,
                onTap: onTap,
                child: const SizedBox(width: 360, child: RootTabBar()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('四个 tab 均分，选中项显示实心图标', (tester) async {
    var tapped = -1;
    await pumpBar(tester, onTap: (index) => tapped = index);

    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.leaderboard_outlined), findsOneWidget);
    expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // 没有中间的唱片封面了。
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.leaderboard_outlined));
    expect(tapped, 1);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    expect(tapped, 3);
  });

  testWidgets('胶囊是液态玻璃，宽度撑满可用空间', (tester) async {
    await pumpBar(tester, onTap: (_) {});

    expect(find.byType(LiquidGlassSurface), findsOneWidget);
    final bar = tester.getSize(find.byType(RootTabBar));
    expect(bar.width, 360);
    expect(bar.height, kRootTabBarHeight);
  });

  testWidgets('四格等宽', (tester) async {
    await pumpBar(tester, onTap: (_) {});
    // 用图标中心算间距：标签文字随语言变化，图标不会。
    final home = tester.getCenter(find.byIcon(Icons.home_rounded));
    final charts = tester.getCenter(find.byIcon(Icons.leaderboard_outlined));
    final playlists = tester.getCenter(
      find.byIcon(Icons.library_music_outlined),
    );
    final settings = tester.getCenter(find.byIcon(Icons.settings_outlined));

    final gap1 = charts.dx - home.dx;
    final gap2 = playlists.dx - charts.dx;
    final gap3 = settings.dx - playlists.dx;
    expect(gap1, greaterThan(80));
    expect(gap2, closeTo(gap1, 0.5));
    expect(gap3, closeTo(gap1, 0.5));
  });
}
