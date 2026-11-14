import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/search_sheet.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/search/presentation/search_provider.dart';
import 'package:koyze/features/search/presentation/search_screen.dart';

void main() {
  test('search sheet owns its drag gesture instead of the stock sheet', () {
    final source = File(
      'lib/core/widgets/search_sheet.dart',
    ).readAsStringSync();

    expect(source, contains('class _SearchSheetRoute extends PopupRoute'));
    expect(source, isNot(contains('showModalBottomSheet')));
    expect(source, contains('onVerticalDragUpdate'));
    expect(source, contains('onVerticalDragEnd'));
    expect(source, contains('Curves.easeInOutCubicEmphasized'));
    // 松手收尾用普通缓出，不再用起点速度为 0 的弹簧曲线。
    expect(source, contains('MotionCurve.easeOutQuart.transform'));
  });

  Future<void> openSheet(
    WidgetTester tester, {
    List<String>? queries,
    List<MusicItem>? results,
  }) async {
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
              return results ?? const <MusicItem>[];
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
                  onPressed: () =>
                      unawaited(showSearchSheet(context, topInset: 96)),
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

  testWidgets('reopening the panel keeps the last results', (tester) async {
    final queries = <String>[];
    final song = MusicItem(
      id: 's1',
      name: '稻香',
      singer: '周杰伦',
      album: '魔杰座',
      duration: const Duration(seconds: 240),
      source: 'tx',
      platform: 'tx',
    );
    await openSheet(tester, queries: queries, results: [song]);

    await tester.enterText(find.byType(TextField), '稻香');
    await tester.pump();
    await tester.tap(find.text('Search'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(queries, ['稻香']);
    expect(find.text('稻香'), findsNWidgets(2));

    // 下滑关掉面板。
    final handle = find.byKey(const ValueKey('search-sheet-drag-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(const Offset(0, 45));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SearchScreen), findsNothing);

    // 再打开：关键词和结果都还在，也没有重新发一次请求。
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('稻香'), findsNWidgets(2));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '稻香',
    );
    expect(queries, ['稻香']);
  });

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

  testWidgets(
    'a short pull returns home without stalling at the release point',
    (tester) async {
      await openSheet(tester);
      final home = tester.getTopLeft(find.byType(SearchScreen)).dy;

      final handle = find.byKey(const ValueKey('search-sheet-drag-handle'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      for (var step = 0; step < 3; step++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final released = tester.getTopLeft(find.byType(SearchScreen)).dy;
      expect(released, greaterThan(home + 40));

      await gesture.up();
      await tester.pump();
      // 松手后的最初 24ms 必须已经明显往回走。收尾曲线曾经是 iosSpring
      // （起点速度为 0），这段时间只挪了不到一成的回程，看着就是悬在松手处。
      await tester.pump(const Duration(milliseconds: 24));
      final early = tester.getTopLeft(find.byType(SearchScreen)).dy;
      final covered = (released - early) / (released - home);
      expect(covered, greaterThan(0.25));

      // 收尾不带回弹：停在原位，不会越过原位再弹回来。
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getTopLeft(find.byType(SearchScreen)).dy,
        closeTo(home, 0.5),
      );
      expect(find.byType(SearchScreen), findsOneWidget);
    },
  );

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

  testWidgets(
    'dragging with the keyboard up still slides the panel off screen',
    (tester) async {
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
    },
  );
}
