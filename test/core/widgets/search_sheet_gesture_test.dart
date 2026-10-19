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

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchStateProvider.overrideWith(
            (ref) => SearchNotifier(
              (query, sourceId, page) async => const [],
              () => 'tx',
            ),
          ),
          hotSearchProvider.overrideWith((ref) async => const ['热歌1']),
          searchHistoryProvider.overrideWith((ref) => SearchHistoryNotifier()),
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
}
