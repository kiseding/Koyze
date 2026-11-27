import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/motion/transition_snapshot.dart';

void main() {
  group('TransitionStart', () {
    testWidgets('首帧还没画完时，动画停在起点不动', (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 400),
      );
      addTearDown(controller.dispose);
      final deferred = TransitionStart.of(controller);

      TransitionStart.hold();
      controller.forward();
      await tester.pump();
      // 模拟首帧很重：动画已经走了 120ms，但页面还没画出来。
      TransitionStart.hold();
      await tester.pump(const Duration(milliseconds: 120));

      expect(controller.value, greaterThan(0.2));
      expect(deferred.value, 0, reason: '首帧期间包装动画必须停在起点，否则第一帧就会跳过去一大截');
      // 首帧结束后 hold 自动释放。
      expect(TransitionStart.holding, isFalse);
      controller.stop();
    });

    testWidgets('首帧之后从当时的进度接着走，终点仍然是 1', (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 400),
      );
      addTearDown(controller.dispose);
      final deferred = TransitionStart.of(controller);

      TransitionStart.hold();
      controller.forward();
      await tester.pump();
      TransitionStart.hold();
      await tester.pump(const Duration(milliseconds: 120));
      expect(deferred.value, 0);

      // 第一帧之后读到的进度成为新的起点：剩下的行程重新铺满 0..1。
      await tester.pump(const Duration(milliseconds: 40));
      final resumed = deferred.value;
      expect(resumed, lessThan(0.15), reason: '释放后要接着起步，不能瞬间跳到一半');

      await tester.pump(const Duration(milliseconds: 200));
      expect(deferred.value, greaterThan(resumed));

      await tester.pump(const Duration(milliseconds: 200));
      expect(deferred.value, 1);
    });

    testWidgets('同一个动画拿到的是同一个包装，不会每次重建都归零', (tester) async {
      final controller = AnimationController(vsync: const TestVSync());
      addTearDown(controller.dispose);
      expect(
        identical(
          TransitionStart.of(controller),
          TransitionStart.of(controller),
        ),
        isTrue,
        reason: 'transitionsBuilder 每次重建都会取一次，换成新包装会把起点记录丢掉',
      );
    });

    testWidgets('返回动画不推迟：手势与 pop 立刻跟手', (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 400),
        value: 1,
      );
      addTearDown(controller.dispose);
      final deferred = TransitionStart.of(controller);

      TransitionStart.hold();
      controller.reverse();
      await tester.pump();
      expect(deferred.value, controller.value, reason: '反向不该被推迟，否则松手瞬间会跳');
      await tester.pump(const Duration(milliseconds: 100));
      expect(deferred.value, controller.value);
      expect(deferred.value, lessThan(1));
      controller.stop();
    });
  });

  group('TransitionSnapshot', () {
    testWidgets('反向动画结束时在最终帧绘制后才释放位图', (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 200),
      );
      addTearDown(controller.dispose);
      final stateKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: TransitionSnapshot(
            key: stateKey,
            animations: <Animation<double>>[controller],
            child: const Scaffold(body: Center(child: Text('收尾'))),
          ),
        ),
      );

      controller.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      controller.reverse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final state = stateKey.currentState! as dynamic;
      expect(
        state.debugSnapshotting,
        isTrue,
        reason: 'dismissed 状态回调时不能在最终反向帧绘制前清掉快照',
      );

      expect(state.debugSnapshotting, isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      expect(state.debugSnapshotting, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('动画进行时用位图绘制，落地后换回实时页面', (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 200),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: TransitionSnapshot(
            animations: <Animation<double>>[controller],
            child: const Scaffold(body: Center(child: Text('页面'))),
          ),
        ),
      );
      expect(find.byType(SnapshotWidget), findsOneWidget);

      controller.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull, reason: '截图不该在真机/测试环境抛异常');
      expect(find.text('页面'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.text('页面'), findsOneWidget);
    });
  });
}
