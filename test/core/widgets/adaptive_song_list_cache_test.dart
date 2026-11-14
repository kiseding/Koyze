import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/card_expand.dart';
import 'package:koyze/core/widgets/adaptive_song_list.dart';

/// 入场动效期间不该白建屏幕外的行：
/// 卡片展开那一帧只有屏幕里这一屏是用户看得见的，列表默认那 250px 缓存区
/// （约 3.5 行）纯属白建，占该帧三成左右。动效播完再恢复，滚动预取不变。
void main() {
  const rowHeight = 72.0;
  const screenHeight = 800.0;
  // 800 / 72 = 11.1 → 12 行刚好铺满一屏。
  const visibleRows = 12;

  int builtRows(WidgetTester tester) => tester
      .widgetList<Text>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && (widget.data?.startsWith('row-') ?? false),
          skipOffstage: false,
        ),
      )
      .length;

  Future<void> pumpApp(
    WidgetTester tester, {
    bool trimCacheWhileEntering = true,
  }) async {
    tester.view.physicalSize = const Size(400, screenHeight);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  expandablePage(
                    const ValueKey('probe'),
                    Scaffold(
                      body: AdaptiveSongList.builder(
                        itemCount: 500,
                        itemExtent: rowHeight,
                        trimCacheWhileEntering: trimCacheWhileEntering,
                        itemBuilder: (context, index) => SizedBox(
                          height: rowHeight,
                          child: Text('row-$index'),
                        ),
                      ),
                    ),
                    expandRect: const Rect.fromLTWH(16, 640, 368, 96),
                  ).createRoute(context),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('入场动效期间只建屏幕内的行', (tester) async {
    await pumpApp(tester);

    final rows = builtRows(tester);
    expect(
      rows,
      lessThanOrEqualTo(visibleRows + 1),
      reason: '动效还在播，屏幕外的行不该建出来（实际建了 $rows 行）',
    );
    expect(rows, greaterThanOrEqualTo(visibleRows - 1));
  });

  testWidgets('动效播完后恢复缓存区，屏幕外照常有行', (tester) async {
    await pumpApp(tester);
    final duringEntrance = builtRows(tester);

    await tester.pumpAndSettle();

    final settled = builtRows(tester);
    expect(
      settled,
      greaterThanOrEqualTo(visibleRows + 3),
      reason: '恢复缓存区后应该有屏幕外的行等着，滚动才不会露白',
    );
    expect(settled, greaterThan(duringEntrance));
  });

  testWidgets('关掉 trim 时入场期间就直接建缓存行', (tester) async {
    await pumpApp(tester, trimCacheWhileEntering: false);

    expect(
      builtRows(tester),
      greaterThanOrEqualTo(visibleRows + 3),
      reason: '显式关掉之后应该退回默认行为',
    );
  });

  testWidgets('恢复缓存后仍能滚到列表末尾', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    final position = tester
        .widget<Scrollable>(find.byType(Scrollable))
        .controller!
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    expect(find.text('row-499'), findsOneWidget);
  });
}
