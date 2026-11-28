import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyze/core/card_expand.dart';

/// 记录被 push 的路由，用来判断转场走的是哪一条分支。
class _RouteRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }

  /// 只有拿到源矩形的页面才会被设成非不透明（做矩形 morph）；
  /// 拿不到就是普通不透明页 + 上滑淡入。
  bool get lastOpaque => (pushed.last as ModalRoute<dynamic>).opaque;
}

/// 模拟「卡片 / 设置行」：点一下先记住自己的矩形，再跳到 [path]。
class _Opener extends StatelessWidget {
  const _Opener({
    required this.label,
    required this.path,
    required this.anchor,
  });

  final String label;
  final String path;
  final GlobalKey anchor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CardExpandSourceVisibility(
        sourceKey: anchor,
        child: RepaintBoundary(
          key: anchor,
          child: ElevatedButton(
            onPressed: () async {
              await captureCardExpandOrigin(anchor.currentContext!);
              if (context.mounted) context.push(path);
            },
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('嵌套层级里的页面也能拿到展开原点', (tester) async {
    debugResetCardExpandOrigins();
    addTearDown(debugResetCardExpandOrigins);

    final recorder = _RouteRecorder();
    final parentAnchor = GlobalKey();
    final childAnchor = GlobalKey();
    final router = GoRouter(
      observers: [recorder],
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: _Opener(
              label: 'open-parent',
              path: '/parent',
              anchor: parentAnchor,
            ),
          ),
        ),
        GoRoute(
          path: '/parent',
          pageBuilder: (context, state) => expandablePage(
            state.pageKey,
            Scaffold(
              body: _Opener(
                label: 'open-child',
                path: '/child',
                anchor: childAnchor,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/child',
          pageBuilder: (context, state) => expandablePage(
            state.pageKey,
            const Scaffold(body: Text('child')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    Future<void> open(GlobalKey anchor, String path) async {
      await tester.runAsync(
        () => captureCardExpandOrigin(anchor.currentContext!),
      );
      router.push(path);
      await tester.pump();
      await tester.pump();
      expect(
        find.byWidgetPredicate((w) => w is RawImage && w.image != null),
        findsOneWidget,
        reason: '测试必须捕获到真实的原行快照',
      );
      await tester.pumpAndSettle();
    }

    await open(parentAnchor, '/parent');
    expect(recorder.lastOpaque, isFalse, reason: '第一层应当从卡片矩形展开');

    await open(childAnchor, '/child');
    expect(find.text('child'), findsOneWidget);
    // 关键：改栈时整栈的 pageBuilder 都会重跑，祖先页先跑。若祖先把这次
    // 新记录的原点消费掉，第三层（设置 → 本地音乐 → 文件管理）就永远只能
    // 上滑淡入——和别的设置页手感对不上。
    expect(recorder.lastOpaque, isFalse, reason: '祖先页不能抢走子页的展开原点');

    double opacityOf(Finder child) => tester
        .widget<Opacity>(
          find.ancestor(of: child, matching: find.byType(Opacity)).first,
        )
        .opacity;

    Future<void> popAndCheck(GlobalKey anchor) async {
      final source = find.byKey(anchor);
      final rawImages = find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image != null,
      );
      expect(opacityOf(source), 1);
      router.pop();
      await tester.pump();
      expect(opacityOf(source), 0, reason: '返回第一帧即隐藏真实原行');
      var sawSnapshot = false;
      var landed = false;
      for (var frame = 0; frame < 50; frame++) {
        final visible = opacityOf(source) == 1;
        final hasSnapshot = rawImages.evaluate().isNotEmpty;
        if (hasSnapshot) {
          sawSnapshot = true;
          expect(visible, isFalse, reason: '第 $frame 帧不能同时显示快照和真实原行');
        } else if (sawSnapshot) {
          expect(visible, isTrue, reason: '快照退场的同一帧必须恢复真实原行');
          landed = true;
        }
        if (!landed) expect(visible, isFalse, reason: '落位前保持隐藏');
        await tester.pump(const Duration(milliseconds: 4));
      }
      await tester.pumpAndSettle();
      expect(sawSnapshot, isTrue, reason: '返回收尾仍然使用快照');
      expect(landed, isTrue);
      expect(opacityOf(source), 1);
    }

    final gesture = await tester.startGesture(const Offset(8, 240));
    await gesture.moveBy(const Offset(48, 0));
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();
    expect(opacityOf(find.byKey(childAnchor)), 0, reason: '侧滑开始即隐藏落点');
    expect(opacityOf(find.byKey(parentAnchor)), 1, reason: '不影响上一层的落点');
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.text('child'), findsOneWidget);
    expect(opacityOf(find.byKey(childAnchor)), 1, reason: '取消侧滑应恢复原行');

    await popAndCheck(childAnchor);
    await popAndCheck(parentAnchor);
  });
}
