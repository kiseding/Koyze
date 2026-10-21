import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/home/presentation/main_scaffold.dart';

/// 回归：顶栏（标题 + 右上角动作）必须跟「视觉上的当前页」走，而不是等
/// 路由切完。
///
/// 之前它读的是 navigationShell.currentIndex，那个值要等横滑补间落到目标
/// 页、`onSelect` 真的 goBranch 之后才变。中间这 300~400ms 里页面已经铺满
/// 屏幕，右上角还挂着上一页的按钮，想点「榜单设置 / 导入歌单」得先等它换
/// 过来——用户反馈的「还是要等那个设置按钮出来才能继续操作」就是这个。
void main() {
  Widget app({
    required int currentIndex,
    required ValueChanged<int> onSelect,
    Key? key,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: SwipeBranchContainer(
          key: key,
          currentIndex: currentIndex,
          onSelect: onSelect,
          children: const [
            ColoredBox(color: Colors.red),
            ColoredBox(color: Colors.green),
            ColoredBox(color: Colors.blue),
            ColoredBox(color: Colors.orange),
          ],
        ),
      ),
    );
  }

  testWidgets('松手判定通过的那一帧，顶栏就切到目标页', (tester) async {
    rootHeaderBranchIndex.value = 0;
    var selected = 0;
    await tester.pumpWidget(app(currentIndex: 0, onSelect: (i) => selected = i));
    await tester.pump();

    // 390 宽的 41%：过了 20% 阈值，一定翻页；但补间还没跑完，
    // 路由（onSelect）也还没被调用。
    await tester.drag(
      find.byType(SwipeBranchContainer),
      const Offset(-160, 0),
    );
    await tester.pump();

    expect(selected, 0, reason: '补间没跑完，路由不该先切');
    expect(rootHeaderBranchIndex.value, 1, reason: '顶栏要跟着页面立刻切');
  });

  testWidgets('拖动不够、弹回原页时顶栏不动', (tester) async {
    rootHeaderBranchIndex.value = 0;
    await tester.pumpWidget(app(currentIndex: 0, onSelect: (_) {}));
    await tester.pump();

    // 10%：不到阈值，松手后弹回。
    await tester.drag(find.byType(SwipeBranchContainer), const Offset(-40, 0));
    await tester.pump();

    expect(rootHeaderBranchIndex.value, 0);
  });

  testWidgets('点击切 tab 时顶栏随动画起跑，不等落定', (tester) async {
    rootHeaderBranchIndex.value = 0;
    final key = GlobalKey<SwipeBranchContainerState>();
    await tester.pumpWidget(
      app(key: key, currentIndex: 0, onSelect: (_) {}),
    );
    await tester.pump();

    key.currentState!.select(2);
    await tester.pump();

    expect(rootHeaderBranchIndex.value, 2);
  });
}
