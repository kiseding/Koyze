import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/search_sheet.dart';
import 'package:koyze/features/search/presentation/search_provider.dart';
import 'package:koyze/features/search/presentation/search_screen.dart';

void main() {
  test('search sheet owns its drag gesture instead of the stock sheet', () {
    final source = File('lib/core/widgets/search_sheet.dart').readAsStringSync();

    expect(source, contains('class _SearchSheetRoute extends PopupRoute'));
    expect(source, isNot(contains('showModalBottomSheet')));
    expect(source, contains('onVerticalDragUpdate'));
    expect(source, contains('onVerticalDragEnd'));
    expect(source, contains('Curves.easeInOutCubicEmphasized'));
  });

  Future<void> openSheet(WidgetTester tester, {List<String>? queries}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchStateProvider.overrideWith(
            () => SearchNotifier((query, sourceId, page) async {
              queries?.add(query);
              return const [];
            }, () => 'tx'),
          ),
          hotSearchProvider.overrideWith((ref) async => const ['热歌1']),
          searchHistoryProvider.overrideWith(SearchHistoryNotifier.new),
          allSearchSourcesProvider.overrideWith(
            (ref) => [
              SearchSourceItem(id: 'all', name: '全网'),
              SearchSourceItem(id: 'tx', name: 'QQ'),
            ],
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => unawaited(
                    showSearchSheet(context, topInset: 96),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('dragging past the threshold dismisses the panel', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.byType(SearchScreen), findsOneWidget);

    final handle = find.byKey(const ValueKey('search-sheet-drag-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(const Offset(0, 45));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    // 关闭分两段：面板先从当前位置滑出屏幕（~200ms），路由再 pop 并播放
    // 反向动画（260ms）。等到路由完全拆除再断言。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SearchScreen), findsNothing);
  });

  testWidgets('a short pull springs back to the open position', (tester) async {
    await openSheet(tester);

    final handle = find.byKey(const ValueKey('search-sheet-drag-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SearchScreen), findsOneWidget);
  });

  testWidgets('panel keeps a gap above the bottom edge', (tester) async {
    await openSheet(tester);

    final panel = tester.getRect(find.byType(SearchScreen));
    final handle = tester.getRect(
      find.byKey(const ValueKey('search-sheet-drag-handle')),
    );
    // 拖拽命中区铺满面板顶部，用它确认面板的位置和宽度。
    expect(handle.top, closeTo(panel.top, 0.5));
    expect(handle.width, closeTo(panel.width, 0.5));
    expect(844 - panel.bottom, closeTo(10, 0.5));
  });

  testWidgets('the trailing capsule is a search button and no inline arrow', (
    tester,
  ) async {
    final queries = <String>[];
    await openSheet(tester, queries: queries);

    // 测试环境跑英文文案：右侧胶囊是 searchAction，不再是 clearResults。
    expect(find.text('Search'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);

    await tester.enterText(find.byType(TextField), '晴天');
    await tester.pump();
    // 有内容时行内只剩清除键，提交交给外面的「搜索」胶囊。
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    await tester.tap(find.text('Search'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(queries, contains('晴天'));
    expect(find.byType(SearchScreen), findsOneWidget);
    // 让自动聚焦的定时器（650ms）走完，避免测试结束时报 pending timer。
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('dragging with the keyboard up still slides the panel off screen', (
    tester,
  ) async {
    await openSheet(tester);
    // 搜索面板默认自动聚焦，键盘弹起时面板只占屏幕上半部分。
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    final handle = find.byKey(const ValueKey('search-sheet-drag-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 60));
    }
    final releasedTop = tester.getTopLeft(find.byType(SearchScreen)).dy;
    await gesture.up();
    await tester.pump();
    // 滑出的动画走完，但路由的反向动画还没结束时取位置：面板必须已经离开
    // 屏幕，而不是停在松手处。
    await tester.pump(const Duration(milliseconds: 240));
    final gone = find.byType(SearchScreen).evaluate().isEmpty;
    final settledTop = gone
        ? double.infinity
        : tester.getTopLeft(find.byType(SearchScreen)).dy;
    expect(settledTop, greaterThan(releasedTop));
    expect(settledTop, greaterThanOrEqualTo(844));

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SearchScreen), findsNothing);
  });
}
