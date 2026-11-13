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
  const _Opener({required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Builder(
        builder: (inner) => RepaintBoundary(
          child: ElevatedButton(
            onPressed: () async {
              await captureCardExpandOrigin(inner);
              if (inner.mounted) inner.push(path);
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
    final router = GoRouter(
      observers: [recorder],
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const _Opener(label: 'open-parent', path: '/parent'),
        ),
        GoRoute(
          path: '/parent',
          pageBuilder: (context, state) => expandablePage(
            state.pageKey,
            const Scaffold(
              body: _Opener(label: 'open-child', path: '/child'),
            ),
          ),
        ),
        GoRoute(
          path: '/child',
          pageBuilder: (context, state) =>
              expandablePage(state.pageKey, const Scaffold(body: Text('child'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open-parent'));
    await tester.pumpAndSettle();
    expect(recorder.lastOpaque, isFalse, reason: '第一层应当从卡片矩形展开');

    await tester.tap(find.text('open-child'));
    await tester.pumpAndSettle();
    expect(find.text('child'), findsOneWidget);
    // 关键：改栈时整栈的 pageBuilder 都会重跑，祖先页先跑。若祖先把这次
    // 新记录的原点消费掉，第三层（设置 → 本地音乐 → 文件管理）就永远只能
    // 上滑淡入——和别的设置页手感对不上。
    expect(recorder.lastOpaque, isFalse, reason: '祖先页不能抢走子页的展开原点');
  });
}
