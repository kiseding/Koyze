import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/card_expand.dart';

/// 把 EdgeSwipeDismiss 放进一个透明（无系统手势）的路由里，测试自绘手势。
Widget _dismissHarness() {
  return MaterialApp(
    theme: ThemeData(platform: TargetPlatform.iOS),
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(
          PageRouteBuilder<void>(
            opaque: false,
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
  );
}

void main() {
  testWidgets('iOS plain page stays opaque so system back gesture works', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final page = expandablePage(const ValueKey('detail'), const SizedBox());
    debugDefaultTargetPlatformOverride = null;

    expect(page.opaque, isTrue);
  });

  testWidgets('iOS card page stays transparent for the expand morph', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final page = expandablePage(
      const ValueKey('detail'),
      const SizedBox(),
      expandRect: const Rect.fromLTWH(20, 20, 120, 80),
    );
    debugDefaultTargetPlatformOverride = null;

    expect(page.opaque, isFalse);
    expect(page.child, isNot(isA<EdgeSwipeDismiss>()));
  });

  testWidgets('full-width page stays transparent for two-way fly', (
    tester,
  ) async {
    final page = expandablePage(
      const ValueKey('full-width-detail'),
      const SizedBox(),
      fullWidthSwipe: true,
    );

    expect(page.opaque, isFalse);
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

  testWidgets(
      'transparent route drives only the inner morph progress (no outer float)',
      (tester) async {
    await tester.pumpWidget(_dismissHarness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(900, 0));
    await tester.pump();
    await tester.pump();

    // 透明路由只发布 morph 进度：没有外层浮窗缩放/位移叠加，
    // 避免出现与卡片缩小程度不一致的浮动层。
    expect(cardDismissProgress.value, greaterThan(0.9));
    final content = find.byKey(const ValueKey('content'));
    final transforms = tester.widgetList<Transform>(
      find.ancestor(of: content, matching: find.byType(Transform)),
    );
    expect(
      transforms.any(
        (w) =>
            w.transform.storage[0] == 0.5 && w.transform.storage[5] == 0.5,
      ),
      isFalse,
    );
    final clips = tester.widgetList<ClipRRect>(find.byType(ClipRRect));
    expect(
      clips.any((clip) => clip.borderRadius == BorderRadius.circular(48)),
      isFalse,
    );
  });

  testWidgets('accepted drag settles while preserving route pop', (
    tester,
  ) async {
    final observer = _PopObserver();
    final app = MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            PageRouteBuilder<void>(
              opaque: false,
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
    );
    await tester.pumpWidget(app);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(220, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // 松手过阈值后从当前位置继续收拢成卡片（进度持续增长 → 1），
    // 成型后 pop；内容位置由内层矩形 morph 决定（无外层位移）。
    expect(cardDismissProgress.value, greaterThan(0.25));
    await tester.pumpAndSettle();
    expect(observer.popCount, 1);
  });

  testWidgets('under-threshold drag settles back without popping', (
    tester,
  ) async {
    final observer = _PopObserver();
    final app = MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            PageRouteBuilder<void>(
              opaque: false,
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
    );
    await tester.pumpWidget(app);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 未过阈值：进度跟手回弹到 0，路由保持。
    expect(cardDismissProgress.value, 0.0);
    expect(observer.popCount, 0);
  });

  testWidgets('opaque route on iOS does not install a custom edge gesture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                opaque: true,
                pageBuilder: (_, _, _) => const EdgeSwipeDismiss(
                  child: ColoredBox(color: Colors.black),
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

    // 系统手势可用时，自绘手势带（左缘窄条）必须完全退出，把左缘
    // 右滑交给 iOS 系统手势（跟手、从当前位置继续）。
    final edges = tester.widgetList<GestureDetector>(
      find.byType(GestureDetector),
    );
    expect(
      edges.where((e) => e.onHorizontalDragUpdate != null),
      isEmpty,
    );
  });

  testWidgets('full-width swipe overrides iOS system edge gesture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                opaque: true,
                pageBuilder: (_, _, _) => const EdgeSwipeDismiss(
                  fullWidthSwipe: true,
                  child: ColoredBox(color: Colors.black),
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

    final dragDetectors = tester.widgetList<GestureDetector>(
      find.byType(GestureDetector),
    );
    expect(
      dragDetectors.where((detector) => detector.onHorizontalDragUpdate != null),
      isNotEmpty,
    );

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(240, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(cardDismissLocked, isFalse);
  });

  testWidgets('full-width transition uses card scale and rounded surface', (
    tester,
  ) async {
    final page = expandablePage(
      const ValueKey('full-width-card-motion'),
      const ColoredBox(color: Colors.black),
      fullWidthSwipe: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => page.transitionsBuilder(
            context,
            const AlwaysStoppedAnimation(0.5),
            const AlwaysStoppedAnimation(0),
            page.child,
          ),
        ),
      ),
    );

    expect(find.byType(Transform), findsWidgets);
    expect(
      tester
          .widgetList<ClipRRect>(find.byType(ClipRRect))
          .any((clip) => clip.borderRadius != BorderRadius.zero),
      isTrue,
    );
  });

  testWidgets(
      'inverted edge drag progresses gradually from full screen instead of jumping',
      (tester) async {
    final progress = ValueNotifier<double>(1);
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                opaque: false,
                pageBuilder: (_, _, _) => EdgeSwipeDismiss(
                  progress: progress,
                  invertProgress: true,
                  child: const ColoredBox(color: Colors.black),
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

    // 拖动刚过 slop（约 18px）时：progress 必须仍接近 1（全屏），
    // 随手指线性下降，绝不瞬间跳到 0（迷你形态）。
    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final early = progress.value;
    debugPrint('early after 40px drag progress=$early');
    expect(early, greaterThan(0.8));
    await gesture.moveBy(const Offset(400, 0));
    await tester.pump();
    final later = progress.value;
    debugPrint('later after 440px drag progress=$later');
    // 拖 55%（440/800）→ 收拢过半，进度应介于 0.3~0.6 之间。
    expect(later, greaterThan(0.3));
    expect(later, lessThan(0.6));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'plain pop without drag collapses the card back to its source position',
      (tester) async {
    const source = Rect.fromLTWH(210, 300, 120, 80);
    final page = expandablePage(
      const ValueKey('detail'),
      const ColoredBox(key: ValueKey('content'), color: Colors.black),
      expandRect: source,
    );

    // 路由反向动画完成（t=1）：卡片必须回到源卡片原位，不能飞到左缘。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => page.transitionsBuilder(
            context,
            const AlwaysStoppedAnimation(0),
            const AlwaysStoppedAnimation(0),
            page.child,
          ),
        ),
      ),
    );

    final positioned = tester
        .widgetList<Positioned>(find.byType(Positioned))
        .where((w) => w.left != null && w.width != null && w.width! > 50)
        .first;
    expect(positioned.left, closeTo(source.left, 1));
    expect(positioned.top, closeTo(source.top, 1));
  });

  testWidgets(
      'card reveal keeps background and content opacity synced to the rect',
      (tester) async {
    final page = expandablePage(
      const ValueKey('detail'),
      const ColoredBox(key: ValueKey('content'), color: Colors.black),
      expandRect: const Rect.fromLTWH(20, 20, 120, 80),
    );

    // 收拢中途（t=0.4）：背景与内容必须与矩形进度同源，不得出现
    // 全屏内容或独立淡出的半透明背景（各自不同步）。
    for (final t in [0.4, 0.7, 0.9]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => page.transitionsBuilder(
              context,
              AlwaysStoppedAnimation<double>(t),
              const AlwaysStoppedAnimation(0),
              page.child,
            ),
          ),
        ),
      );
      final synced = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((w) => w.opacity > 0 && w.opacity < 1)
          .map((w) => w.opacity)
          .toList();
      // 背景与内容必须取相同矩形进度（成对出现）；快照仅收尾浮现。
      // 收缩早期保持实心（无过渡透明度），允许该帧没有过渡元素。
      if (synced.isNotEmpty) {
        final grouped = synced.fold<Map<double, int>>({}, (m, o) {
          m[o] = (m[o] ?? 0) + 1;
          return m;
        });
        expect(grouped.values.any((count) => count >= 2), isTrue);
      }
    }
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
