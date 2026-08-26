import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyze/core/card_expand.dart';

void main() {
  testWidgets('iOS expandable route keeps the previous page visible', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final page = expandablePage(const ValueKey('detail'), const SizedBox());
    debugDefaultTargetPlatformOverride = null;

    expect(page, isA<CustomTransitionPage<Object?>>());
    expect(page.opaque, isFalse);
    expect(page.child, isNot(isA<EdgeSwipeDismiss>()));
  });

  testWidgets('edge swipe wraps the complete card transition', (tester) async {
    final page = expandablePage(
      const ValueKey('detail'),
      const ColoredBox(key: ValueKey('content'), color: Colors.black),
      expandRect: const Rect.fromLTWH(20, 20, 120, 80),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => page.transitionsBuilder(
            context,
            const AlwaysStoppedAnimation(1),
            const AlwaysStoppedAnimation(0),
            page.child,
          ),
        ),
      ),
    );

    expect(find.byType(EdgeSwipeDismiss), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(EdgeSwipeDismiss),
        matching: find.byKey(const ValueKey('content')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('iOS drag becomes a rounded half-size floating window', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: const EdgeSwipeDismiss(
          child: ColoredBox(key: ValueKey('content'), color: Colors.black),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(900, 0));
    await tester.pump();

    final content = find.byKey(const ValueKey('content'));
    final transform = tester.widgetList<Transform>(
      find.ancestor(of: content, matching: find.byType(Transform)),
    );
    expect(
      transform.any(
        (widget) =>
            widget.transform.storage[0] == 0.5 &&
            widget.transform.storage[5] == 0.5,
      ),
      isTrue,
    );
    final clips = tester.widgetList<ClipRRect>(find.byType(ClipRRect));
    expect(
      clips.any((clip) => clip.borderRadius == BorderRadius.circular(48)),
      isTrue,
    );
  });

  testWidgets('accepted drag settles while preserving route pop', (
    tester,
  ) async {
    final observer = _PopObserver();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: const Duration(milliseconds: 280),
                pageBuilder: (_, _, _) => const EdgeSwipeDismiss(
                  child: ColoredBox(
                    key: ValueKey('content'),
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(220, 0));
    await tester.pump();
    final content = find.byKey(const ValueKey('content'));
    final dragged = tester.getTopLeft(content).dx;
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // 松手过阈值后页面从拖动位置"归位"（滑回原位），随后才 pop 播放
    // 收拢关闭动效；归位过程中位置应小于拖动位置且逐渐回到 0。
    final settling = tester.getTopLeft(content).dx;
    expect(settling, greaterThan(0));
    expect(settling, lessThan(dragged));
    await tester.pumpAndSettle();
    expect(observer.popCount, 1);
  });

  testWidgets('under-threshold drag settles back without popping', (
    tester,
  ) async {
    final observer = _PopObserver();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: const Duration(milliseconds: 280),
                pageBuilder: (_, _, _) => const EdgeSwipeDismiss(
                  child: ColoredBox(
                    key: ValueKey('content'),
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    final content = find.byKey(const ValueKey('content'));
    final dragged = tester.getTopLeft(content).dx;
    await gesture.up();
    await tester.pumpAndSettle();

    // 未过阈值：跟手回弹到 0，路由保持。
    expect(tester.getTopLeft(content).dx, 0);
    expect(tester.getTopLeft(content).dx, lessThan(dragged));
    expect(observer.popCount, 0);
  });
}

class _PopObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}
