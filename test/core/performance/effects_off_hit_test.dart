import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyze/core/card_expand.dart';
import 'package:koyze/core/motion/motion_tokens.dart';
import 'package:koyze/core/performance/low_memory.dart';
import 'package:koyze/core/player_route_progress.dart';
import 'package:koyze/core/widgets/koyze_sheet.dart';

void main() {
  tearDown(() {
    LowMemory.active = false;
    playerRouteProgress.value = 0;
    playerRouteDismissLocked = false;
    debugResetCardExpandOrigins();
  });

  testWidgets('simplified effects keep an expanded page tappable', (
    tester,
  ) async {
    LowMemory.active = true;
    var taps = 0;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/next'),
              child: const Text('open-page'),
            ),
          ),
        ),
        GoRoute(
          path: '/next',
          pageBuilder: (_, state) => expandablePage(
            state.pageKey,
            Scaffold(
              body: TextButton(
                onPressed: () => taps++,
                child: const Text('page-action'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open-page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('page-action'), findsOneWidget);
    await tester.tap(find.text('page-action'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('simplified effects keep a settings dialog tappable', (
    tester,
  ) async {
    LowMemory.active = true;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    opaque: false,
                    barrierDismissible: true,
                    barrierColor: Colors.black54,
                    transitionDuration: effectsDuration(
                      const Duration(milliseconds: 240),
                    ),
                    reverseTransitionDuration: effectsDuration(
                      const Duration(milliseconds: 180),
                    ),
                    pageBuilder: (_, _, _) => Center(
                      child: TextButton(
                        onPressed: () => taps++,
                        child: const Text('dialog-action'),
                      ),
                    ),
                    transitionsBuilder: (_, animation, _, child) {
                      final curved = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutBack,
                        reverseCurve: Curves.easeInCubic,
                      );
                      return FadeTransition(
                        opacity: Tween<double>(begin: 0, end: 1).animate(curved),
                        child: child,
                      );
                    },
                  ),
                );
              },
              child: const Text('open-dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('dialog-action'), findsOneWidget);
    await tester.tap(find.text('dialog-action'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('simplified effects keep a bottom sheet tappable', (
    tester,
  ) async {
    LowMemory.active = true;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showKoyzeSheet<void>(
                  context: context,
                  builder: (_) => TextButton(
                    onPressed: () => taps++,
                    child: const Text('sheet-action'),
                  ),
                );
              },
              child: const Text('open-sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-sheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('sheet-action'), findsOneWidget);
    await tester.tap(find.text('sheet-action'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a completed player route publishes progress immediately', (
    tester,
  ) async {
    playerRouteProgress.value = 0;
    final controller = AnimationController(
      vsync: tester,
      duration: Duration.zero,
      value: 1,
    );
    addTearDown(controller.dispose);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );
    addTearDown(curved.dispose);

    await tester.pumpWidget(
      PlayerRouteProgressBridge(
        animation: curved,
        child: const SizedBox.expand(),
      ),
    );
    await tester.pump();

    expect(playerRouteProgress.value, 1);
  });
}
