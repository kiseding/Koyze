import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/core/widgets/pressable.dart';
import 'package:koyze/core/widgets/root_shell_layout.dart';
import 'package:koyze/features/cloud/presentation/cloud_provider.dart';
import 'package:koyze/features/home/presentation/main_scaffold.dart';

void main() {
  /// 手机横屏的逻辑高度（393）。低于 420，侧栏走紧凑档，行高 46。
  const railHeight = 393.0;
  const compactExtent = 46.0;

  Future<void> pumpRail(
    WidgetTester tester, {
    required void Function(int) onTap,
  }) async {
    tester.view.physicalSize = const Size(800, railHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 默认会 refresh，测试里不要真去连网。
          cloudSessionProvider.overrideWith(
            () => CloudSessionNotifier(
              autoRefresh: false,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: railHeight,
              child: RootSideNav(
                selectedIndex: 0,
                headers: RootHeaderController(),
                onTap: onTap,
                currentPath: '/',
                onOpenSync: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('侧栏 tab 的热区是整行高，不只是图标那一条', (tester) async {
    final tapped = <int>[];
    await pumpRail(tester, onTap: tapped.add);

    // 选中态是实心 home，未选中时是描边；这里 selectedIndex 0，取实心那颗。
    final home = find.byIcon(Icons.home).first;
    final hot = find
        .ancestor(of: home, matching: find.byType(Pressable))
        .first;

    // 热区必须顶到行高。原来 Pressable 只包内容 Row（约 23 高），
    // 行高 46 里上下各一半点不动——横屏侧栏"tab 很难点"就是这个。
    expect(tester.getSize(hot).height, compactExtent);

    // 从图标中心往上 16pt：仍在行内（半行 23），但远在内容条之外。
    final iconCenter = tester.getCenter(home);
    await tester.tapAt(iconCenter - const Offset(0, 16));
    await tester.pumpAndSettle();
    expect(tapped, [0]);
  });

  testWidgets('行与行之间的缝隙不会误触', (tester) async {
    final tapped = <int>[];
    await pumpRail(tester, onTap: tapped.add);

    final homeCenter = tester.getCenter(find.byIcon(Icons.home).first);
    // 紧凑档行高 46、间距 6：中心下方 25 已落进下面的缝隙。
    await tester.tapAt(homeCenter + const Offset(0, 25));
    await tester.pumpAndSettle();
    expect(tapped, isEmpty);
  });
}
