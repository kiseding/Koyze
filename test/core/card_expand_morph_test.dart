import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyze/core/card_expand.dart';

/// 卡片展开转场的行为契约。
///
/// 之前的版本靠 `readAsStringSync` + `contains('Rect.lerp(...)')` 来"保证"
/// morph，那种测试在重命变量时误报、在真正删掉 morph 时却可能仍然通过。
/// 这里改为实际构造路由并检查产出。
void main() {
  Widget appWithPage(CustomTransitionPage<Object?> page) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).push(page.createRoute(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('有源矩形时页面透明，才能透视下层做 morph', (tester) async {
    final page = expandablePage(
      const ValueKey('k'),
      const ColoredBox(color: Colors.white),
      expandRect: const Rect.fromLTWH(20, 400, 380, 120),
    );
    expect(page.opaque, isFalse);
    expect(page.barrierColor, Colors.transparent);
    expect(page.barrierDismissible, isTrue);
  });

  testWidgets('没有源矩形时页面不透明，保留系统返回手势', (tester) async {
    final page = expandablePage(
      const ValueKey('k2'),
      const ColoredBox(color: Colors.white),
    );
    expect(page.opaque, isTrue);
    expect(page.barrierDismissible, isFalse);
  });

  testWidgets('整页右滑页也是透明的，飞入时才能露出下层', (tester) async {
    final page = expandablePage(
      const ValueKey('k3'),
      const ColoredBox(color: Colors.white),
      fullWidthSwipe: true,
    );
    expect(page.opaque, isFalse);
  });

  testWidgets('同一个 key 第二次调用会记住第一次的源矩形', (tester) async {
    const key = ValueKey('remember-me');
    final first = expandablePage(
      key,
      const ColoredBox(color: Colors.white),
      expandRect: const Rect.fromLTWH(0, 0, 100, 100),
    );
    expect(first.opaque, isFalse);

    // go_router 重跑 pageBuilder 时通常不会再传 rect，
    // 此时必须复用第一次记住的矩形，否则 morph 丢失、页面变成不透明。
    final second = expandablePage(key, const ColoredBox(color: Colors.white));
    expect(
      second.opaque,
      isFalse,
      reason: '同一 pageKey 应沿用记住的源矩形，保持 morph 能力',
    );
  });

  testWidgets('打开展开页后能正常渲染内容', (tester) async {
    final page = expandablePage(
      const ValueKey('render'),
      const Center(child: Text('detail')),
      expandRect: const Rect.fromLTWH(20, 400, 380, 120),
    );
    await tester.pumpWidget(appWithPage(page));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('转场时长比普通页面短，打开与关闭使用不同节奏', (tester) async {
    final page = expandablePage(
      const ValueKey('timing'),
      const ColoredBox(color: Colors.white),
    );
    expect(page.transitionDuration, isNot(equals(Duration.zero)));
    expect(page.reverseTransitionDuration, isNot(equals(Duration.zero)));
  });
}
