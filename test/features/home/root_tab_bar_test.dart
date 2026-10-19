import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/theme/app_colors.dart';
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
    bool settle = true,
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  S stringsOf(WidgetTester tester) {
    return S.of(tester.element(find.byType(RootTabBar)));
  }

  List<String> labelsOf(WidgetTester tester) {
    final s = stringsOf(tester);
    return <String>[s.home, s.charts, s.playlists, s.settings];
  }

  Finder tabFinder(int index) => find.byKey(ValueKey<String>('root-tab-$index'));

  Size tabSize(WidgetTester tester, int index) =>
      tester.getSize(tabFinder(index));

  /// 文字外面那层 Opacity 就是它的显隐。收起态是 0 而不是「不存在」——
  /// 文字始终在树上，这样展开时才有得淡入，也不会在切 tab 时长出来。
  double textOpacity(WidgetTester tester, String label) {
    final finder = find.ancestor(
      of: find.text(label),
      matching: find.byType(Opacity),
    );
    return tester.widget<Opacity>(finder.first).opacity;
  }

  testWidgets('未选中只有图标，选中项才把名字显出来', (tester) async {
    await pumpBar(tester, onTap: (_) {});

    final labels = labelsOf(tester);
    // 四个名字都在树上，但只有选中那个不透明。
    expect(textOpacity(tester, labels[0]), 1);
    for (final label in labels.skip(1)) {
      expect(textOpacity(tester, label), 0, reason: label);
    }

    // 图标：选中是实心，其余是描边。
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(find.byIcon(Icons.leaderboard_outlined), findsOneWidget);
    expect(find.byIcon(Icons.leaderboard_rounded), findsNothing);
  });

  testWidgets('选中项向外展开，收起项只有图标那么宽', (tester) async {
    await pumpBar(tester, onTap: (_) {});

    final selected = tabSize(tester, 0);
    final idle = tabSize(tester, 1);
    expect(selected.width, greaterThan(idle.width + 20));
    expect(selected.height, kRootTabBarHeight);
    expect(idle.height, kRootTabBarHeight);

    // 整条从左起排，和标题同一条轴线。
    final barLeft = tester.getTopLeft(find.byType(RootTabBar)).dx;
    expect(tester.getTopLeft(tabFinder(0)).dx, barLeft);
  });

  testWidgets('切换时一收一放走同一条时间线，中间态确实在动', (tester) async {
    await pumpBar(tester, onTap: (_) {});
    final openWidth = tabSize(tester, 0).width;
    final idleWidth = tabSize(tester, 1).width;

    await pumpBar(tester, onTap: (_) {}, selected: 1, settle: false);
    // 起点仍在原处：动画刚起步。
    expect(tabSize(tester, 0).width, closeTo(openWidth, 0.5));

    await tester.pump(const Duration(milliseconds: 110));
    final leaving = tabSize(tester, 0).width;
    final arriving = tabSize(tester, 1).width;
    // 两边都停在中间，而不是瞬切。
    expect(leaving, lessThan(openWidth));
    expect(leaving, greaterThan(idleWidth));
    expect(arriving, greaterThan(idleWidth));

    await tester.pumpAndSettle();
    expect(tabSize(tester, 0).width, closeTo(idleWidth, 0.5));
    expect(tabSize(tester, 1).width, greaterThan(idleWidth + 20));
    expect(textOpacity(tester, labelsOf(tester)[1]), 1);
    expect(textOpacity(tester, labelsOf(tester)[0]), 0);
  });

  testWidgets('四个图标加一个展开项不会撑破整条', (tester) async {
    await pumpBar(tester, onTap: (_) {});

    // 展开宽度由文字宽度决定，中英文都不该把整条撑到溢出。
    final total = [
      for (var i = 0; i < 4; i++) tabSize(tester, i).width,
    ].fold<double>(0, (a, b) => a + b);
    expect(total, lessThan(barWidth));
  });

  testWidgets('点击回调带正确索引，图标本身就是热区', (tester) async {
    var tapped = -1;
    await pumpBar(tester, onTap: (index) => tapped = index);

    await tester.tap(find.byIcon(Icons.leaderboard_outlined));
    expect(tapped, 1);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    expect(tapped, 3);
  });

  testWidgets('导航不沾强调色，选中只靠明度和字重', (tester) async {
    await pumpBar(tester, onTap: (_) {});

    final context = tester.element(find.byType(RootTabBar));
    final onSurface = AppColors.onScaffold(context);
    final idle = AppColors.secondaryText(context);

    expect(
      tester.widget<Icon>(find.byIcon(Icons.home_rounded)).color,
      onSurface,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.leaderboard_outlined)).color,
      idle,
    );
    // 换主题色时这条栏不该跟着变，所以源码里不该出现 accentOf。
    expect(
      File('lib/core/widgets/root_tab_bar.dart').readAsStringSync(),
      isNot(contains('accentOf')),
    );
  });

  testWidgets('导航不再铺玻璃，也不再是分段轨道', (tester) async {
    await pumpBar(tester, onTap: (_) {});

    expect(find.byType(LiquidGlassSurface), findsNothing);
    expect(tester.getSize(find.byType(RootTabBar)).height, kRootTabBarHeight);
  });
}
