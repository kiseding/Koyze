import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/core/widgets/liquid_glass.dart';
import 'package:koyze/core/widgets/root_tab_bar.dart';
import 'package:koyze/l10n/app_strings.dart';

void main() {
  const screen = Size(390, 844);
  const barWidth = 360.0;

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
                child: const SizedBox(width: barWidth, child: RootTabBar()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  S stringsOf(WidgetTester tester) {
    return S.of(tester.element(find.byType(RootTabBar)));
  }

  List<String> labelsOf(WidgetTester tester) {
    final s = stringsOf(tester);
    return <String>[s.home, s.charts, s.playlists, s.settings];
  }

  testWidgets('四个栏目名并排，点击回调带正确索引', (tester) async {
    var tapped = -1;
    await pumpBar(tester, onTap: (index) => tapped = index);

    final labels = labelsOf(tester);
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }

    // 没有中间封面，也没有图标——分段控件只靠文字。
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);
    expect(find.byIcon(Icons.home_rounded), findsNothing);

    await tester.tap(find.text(labels[1]));
    expect(tapped, 1);

    await tester.tap(find.text(labels[3]));
    expect(tapped, 3);
  });

  testWidgets('分段控件撑满宽度，高度是 kRootTabBarHeight', (tester) async {
    await pumpBar(tester, onTap: (_) {});

    final bar = tester.getSize(find.byType(RootTabBar));
    expect(bar.width, barWidth);
    expect(bar.height, kRootTabBarHeight);

    // 导航是结构件，不该再包一层毛玻璃。
    expect(find.byType(LiquidGlassSurface), findsNothing);
  });

  testWidgets('四格等宽', (tester) async {
    await pumpBar(tester, onTap: (_) {});

    final labels = labelsOf(tester);
    final centers = [
      for (final label in labels) tester.getCenter(find.text(label)).dx,
    ];

    final gap1 = centers[1] - centers[0];
    final gap2 = centers[2] - centers[1];
    final gap3 = centers[3] - centers[2];
    expect(gap1, greaterThan(80));
    expect(gap2, closeTo(gap1, 0.5));
    expect(gap3, closeTo(gap1, 0.5));
  });

  testWidgets('选中药丸停在被选中的那一格', (tester) async {
    await pumpBar(tester, onTap: (_) {});
    const segment = (barWidth - 6) / 4;

    AnimatedPositioned pill() =>
        tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));

    // 首格时药丸贴左边（轨道内边距 3 由 Padding 给出，left 从 0 起算）。
    expect(pill().left, 0);

    await pumpBar(tester, onTap: (_) {}, selected: 2);
    expect(pill().left, closeTo(segment * 2, 0.01));
    expect(pill().width, closeTo(segment, 0.01));
  });
}
