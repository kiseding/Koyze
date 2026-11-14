// 回归：横滑切页 / 纵向滚动谁接管，必须由**方向**决定，而不是由触摸采样粒度
// 或平台上报的 touchSlop 决定。
//
// 背景：旧实现靠 `hasSufficientGlobalDistanceToAccept`（累计路程 > 自己的
// slop）决胜，横滑这边写死 16，而内层列表用的是
// `MediaQuery.gestureSettings.touchSlop ?? kTouchSlop`——Android / 鸿蒙会
// 把它上报成 8dp，于是列表只要移动 8px 就能赢，横滑却要 16。一次 onTouch
// 给出 20~40px 的 delta 时两边在同一帧双双越界，arena 按命中顺序派发（内层
// 列表先拿到），这一下就彻底没有反应：页面不动，列表也不动（它只认纵向）。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/home/presentation/main_scaffold.dart';

Widget _page(String tag, ScrollController controller) {
  return ListView.builder(
    key: Key('list-$tag'),
    controller: controller,
    itemCount: 40,
    itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$tag-$i')),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ScrollController> controllers,
  required ValueChanged<int> onSelect,
  double? platformSlop,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          gestureSettings: DeviceGestureSettings(touchSlop: platformSlop),
        ),
        child: SwipeBranchContainer(
          currentIndex: 0,
          onSelect: onSelect,
          children: [
            _page('home', controllers[0]),
            _page('search', controllers[1]),
            _page('playlist', controllers[2]),
          ],
        ),
      ),
    ),
  );
}

void main() {
  late List<ScrollController> controllers;

  setUp(() {
    controllers = [ScrollController(), ScrollController(), ScrollController()];
  });

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
  });

  testWidgets('细采样横滑仍然切页', (tester) async {
    var selected = 0;
    await _pump(
      tester,
      controllers: controllers,
      onSelect: (i) => selected = i,
    );

    final gesture = await tester.startGesture(const Offset(300, 400));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(-12, 2));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 1, reason: '20 帧、每帧 12px 的横滑必须切到下一页');
    expect(controllers[0].offset, 0, reason: '横滑不该顺带滚动列表');
  });

  // 这一条是鸿蒙/安卓真机出问题的场景：平台把 touchSlop 上报成 8dp，
  // 列表比横滑更早越界，一帧 40px 的横滑会被判成纵向。
  testWidgets('平台 slop=8 时单帧 40px 横滑也切页', (tester) async {
    var selected = 0;
    await _pump(
      tester,
      controllers: controllers,
      onSelect: (i) => selected = i,
      platformSlop: 8,
    );

    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(-40, 10));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-12, 1));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 1, reason: '单帧 40px、偏 14° 的横滑不能被列表吃掉');
    expect(controllers[0].offset, 0);
  });

  testWidgets('单帧 24px 的斜横滑也切页', (tester) async {
    var selected = 0;
    await _pump(
      tester,
      controllers: controllers,
      onSelect: (i) => selected = i,
    );

    // 一帧走 24px 横向 + 6px 纵向（约 14°）。
    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(-24, 6));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-12, 1));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 1, reason: '斜 14° 的横滑属于横滑，不能被列表吃掉');
  });

  testWidgets('纵向滑动滚动列表，不切页', (tester) async {
    var selected = 0;
    await _pump(
      tester,
      controllers: controllers,
      onSelect: (i) => selected = i,
    );

    final gesture = await tester.startGesture(const Offset(200, 500));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(2, -12));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 0, reason: '纵向手势不能翻页');
    expect(controllers[0].offset, greaterThan(0), reason: '列表要真的滚起来');
  });

  testWidgets('斜 45° 归列表：滚起来且不翻页', (tester) async {
    var selected = 0;
    await _pump(
      tester,
      controllers: controllers,
      onSelect: (i) => selected = i,
    );

    final gesture = await tester.startGesture(const Offset(200, 500));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(-8, -8));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 0, reason: '45° 属于纵向，翻页会让人莫名其妙跳出当前列表');
    expect(controllers[0].offset, greaterThan(0));
  });

  testWidgets('手指先竖后横：已经让给列表就不中途抢回来', (tester) async {
    var selected = 0;
    await _pump(
      tester,
      controllers: controllers,
      onSelect: (i) => selected = i,
    );

    final gesture = await tester.startGesture(const Offset(200, 500));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(1, -12));
      await tester.pump();
    }
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-14, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 0, reason: '手势一旦判给列表，就不该在拖动中途翻页');
  });
}
