import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/deferred_until_route_settled.dart';

void main() {
  testWidgets('不在路由里时立刻构建，不做推迟', (tester) async {
    var settled = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DeferredUntilRouteSettled(
          onSettled: () => settled++,
          child: const Text('content'),
        ),
      ),
    );
    expect(find.text('content'), findsOneWidget);
    await tester.pump();
    expect(settled, 0);
  });

  testWidgets('路由入场动画期间只显示占位，动画结束后才挂载内容', (tester) async {
    var settled = 0;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: DeferredUntilRouteSettled(
                        onSettled: () => settled++,
                        placeholder: const Text('placeholder'),
                        child: const Text('content'),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('content'), findsNothing, reason: '动效还在播，不能建重内容');
    expect(find.text('placeholder'), findsOneWidget);
    expect(settled, 0);

    await tester.pumpAndSettle();

    expect(find.text('content'), findsOneWidget);
    expect(find.text('placeholder'), findsNothing);
    await tester.pump();
    expect(settled, 1, reason: '挂载后只回调一次，供页面补做定位');
  });

  testWidgets('零时长过渡立刻算完成，不会把内容卡在占位', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    pageBuilder: (_, __, ___) => const Scaffold(
                      body: DeferredUntilRouteSettled(
                        placeholder: Text('placeholder'),
                        child: Text('content'),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();

    expect(find.text('content'), findsOneWidget);
  });
}
