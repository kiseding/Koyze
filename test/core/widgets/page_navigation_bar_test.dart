import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/koyze_modal.dart';
import 'package:koyze/core/widgets/page_navigation_bar.dart';

/// 页码选择弹窗：块要够大，且不能被安全区撑出上下空白。
///
/// 之前 GridView 没显式给 padding，滚动组件默认会把 `MediaQuery.padding`
/// 的上下安全区当成内边距吃掉（刘海屏 47 + 34），弹窗里就成了标题下面
/// 空一大块、最后一个块下面再空一块。
Future<void> _openPicker(WidgetTester tester, {int pageCount = 20}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 844),
        padding: EdgeInsets.only(top: 47, bottom: 34),
        viewPadding: EdgeInsets.only(top: 47, bottom: 34),
      ),
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PageNavigationBar(
              pageIndex: 0,
              pageCount: pageCount,
              onPageChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(TextButton).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('page blocks are comfortable tap targets', (tester) async {
    await _openPicker(tester);

    final block = find
        .ancestor(of: find.text('1'), matching: find.byType(Material))
        .first;
    final size = tester.getSize(block);
    expect(size.width, greaterThanOrEqualTo(60));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('the grid does not inherit the vertical safe area', (
    tester,
  ) async {
    await _openPicker(tester);

    final title = find
        .descendant(of: find.byType(KoyzeDialog), matching: find.byType(Text))
        .first;
    final firstBlock = find
        .ancestor(of: find.text('1'), matching: find.byType(Material))
        .first;

    final gap = tester.getRect(firstBlock).top - tester.getRect(title).bottom;
    // 标题与网格之间只有 8pt 的固定间距；超过 30 说明网格把安全区吃进来了。
    expect(gap, lessThan(30));
  });

  testWidgets('the last row is never clipped in half', (tester) async {
    await _openPicker(tester, pageCount: 23);

    final lastBlock = find
        .ancestor(of: find.text('23'), matching: find.byType(Material))
        .first;
    // 网格高度按整行算：最后一个页码块要完整落在可视区域内。
    final grid = tester.getRect(find.byType(GridView));
    expect(
      tester.getRect(lastBlock).bottom,
      lessThanOrEqualTo(grid.bottom + 0.5),
    );
  });

  testWidgets('tapping a page reports the zero-based index', (tester) async {
    var picked = -1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PageNavigationBar(
              pageIndex: 0,
              pageCount: 20,
              onPageChanged: (index) => picked = index,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('7'));
    await tester.pumpAndSettle();

    expect(picked, 6);
  });
}
