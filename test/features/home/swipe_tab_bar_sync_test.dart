// 回归：连续快甩时 tab 条的胶囊必须一直跟着页面坐标走。
//
// 背景：胶囊原先是按「朝相邻页的进度 0..1」驱动的，而这个进度被钳在 ±1。
// 连续快甩时手指会在上一次补间没跑完时又起手，页面坐标已经越过整页（比如
// 1.2），进度却卡在 1——胶囊于是冻在「下一颗已张开」那一帧不再变化，直到
// 落定才跳到目标，看起来就是切换动效被省略了。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/core/widgets/root_tab_bar.dart';
import 'package:koyze/features/home/presentation/main_scaffold.dart';

Widget _page(String tag, ScrollController controller) {
  return ListView.builder(
    key: Key('list-$tag'),
    controller: controller,
    itemCount: 40,
    itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$tag-$i')),
  );
}

void main() {
  testWidgets('连续快甩越过一整页，胶囊继续跟随而不是冻住', (tester) async {
    final controllers = List.generate(4, (_) => ScrollController());
    final selected = ValueNotifier<int>(0);
    rootBranchDragPosition.value = null;
    rootBranchSettle.value = null;
    addTearDown(() {
      rootBranchDragPosition.value = null;
      rootBranchSettle.value = null;
      for (final c in controllers) {
        c.dispose();
      }
      selected.dispose();
    });

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: selected,
            builder: (context, index, _) => RootTabScope(
              selectedIndex: index,
              onTap: (i) => selected.value = i,
              child: Column(
                children: [
                  const RootTabBar(),
                  Expanded(
                    child: SwipeBranchContainer(
                      currentIndex: index,
                      onSelect: (i) => selected.value = i,
                      children: [
                        _page('home', controllers[0]),
                        _page('search', controllers[1]),
                        _page('playlist', controllers[2]),
                        _page('settings', controllers[3]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double tabWidth(int index) =>
        tester.getSize(find.byKey(ValueKey<String>('root-tab-$index'))).width;

    final idle = tabWidth(1);
    expect(tabWidth(0), greaterThan(idle + 20), reason: '起始选中项是张开的');

    // 第一次甩：约 0.8 页，松手后只给两帧，补间还挂在半路。
    final first = await tester.startGesture(const Offset(320, 500));
    for (var i = 0; i < 8; i++) {
      await first.moveBy(const Offset(-40, 2));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await first.up();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // 第二次接着甩：坐标越过一整页。
    final second = await tester.startGesture(const Offset(320, 500));
    for (var i = 0; i < 4; i++) {
      await second.moveBy(const Offset(-40, 2));
      await tester.pump(const Duration(milliseconds: 8));
    }

    // 旧实现里进度被钳在 1，2 号始终是收起宽度（冻住）。
    expect(
      tabWidth(2),
      greaterThan(idle + 4),
      reason: '页面已经越过一整页，胶囊必须继续跟到下一颗，而不是停在上限',
    );
    final crossed = tabWidth(2);

    // 再往前一点：2 号还得继续长，说明它跟的是手指而不是一个封顶的进度。
    for (var i = 0; i < 3; i++) {
      await second.moveBy(const Offset(-30, 2));
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(
      tabWidth(2),
      greaterThan(crossed + 4),
      reason: '越过整页之后胶囊仍要逐帧跟随，不能停在那儿',
    );
    expect(tabWidth(1), lessThan(crossed + 60), reason: '1 号同时在收，不是只长不收');

    await second.up();
    await tester.pumpAndSettle();

    // 落定后胶囊停在真正的选中项上，不会回弹。
    expect(selected.value, isNot(0));
    expect(
      tabWidth(selected.value),
      greaterThan(idle + 20),
      reason: '落定后选中的那颗必须是张开的',
    );
  });
}
