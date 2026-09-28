import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/root_shell_layout.dart';
import 'package:koyze/features/home/presentation/independent_side_rail.dart';

void main() {
  test('side navigation is used for desktop and landscape windows', () {
    expect(
      shouldUseSideNavigation(
        size: const Size(390, 844),
        orientation: Orientation.portrait,
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isFalse,
    );
    expect(
      shouldUseSideNavigation(
        size: const Size(390, 844),
        orientation: Orientation.portrait,
        platform: TargetPlatform.windows,
        isWeb: false,
        forceLandscape: true,
      ),
      isTrue,
    );
    expect(
      shouldUseSideNavigation(
        size: const Size(844, 390),
        orientation: Orientation.landscape,
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isTrue,
    );
    expect(
      shouldUseSideNavigation(
        size: const Size(900, 700),
        orientation: Orientation.landscape,
        platform: TargetPlatform.windows,
        isWeb: false,
      ),
      isTrue,
    );
    expect(
      shouldUseSideNavigation(
        size: const Size(900, 700),
        orientation: Orientation.landscape,
        platform: TargetPlatform.windows,
        isWeb: true,
      ),
      isTrue,
    );
  });

  testWidgets('root shell layout state is inherited by root pages', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RootShellLayout(usesSideNavigation: true, child: _LayoutProbe()),
      ),
    );

    expect(find.text('side'), findsOneWidget);
  });

  test('root tabs and the mini player share the home content width', () {
    expect(shellContentWidth(390), 390);
    expect(shellContentWidth(719), 719);
    expect(shellContentWidth(720), closeTo(720 * 0.82, 0.01));
    expect(shellContentWidth(1600), 900);

    expect(
      miniPlayerSideInset(pageWidth: 390, usesSideNavigation: false),
      3,
    );
    expect(
      miniPlayerSideInset(pageWidth: 800, usesSideNavigation: true),
      closeTo((800 - 800 * 0.82) / 2, 0.01),
    );
    expect(
      miniPlayerSideInset(pageWidth: 1600, usesSideNavigation: true),
      closeTo((1600 - 900) / 2, 0.01),
    );
  });

  test('side rail width grows with the window and keeps a middle gap', () {
    expect(sideRailContentWidth(800), 180);
    expect(sideRailContentWidth(1200), closeTo(264, 0.01));
    expect(sideRailContentWidth(1600), 320);
    expect(sideRailContentWidth(800), isNot(sideRailContentWidth(1200)));
  });

  testWidgets('portrait header actions are published into the side rail', (
    tester,
  ) async {
    final headers = RootHeaderController();
    addTearDown(headers.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RootHeaderScope(
          controller: headers,
          child: const RootHeaderPublisher(
            index: 0,
            title: 'Koyze',
            actions: [Text('settings-action')],
          ),
        ),
      ),
    );
    await tester.pump();

    final header = headers.headerFor(0);
    expect(header?.title, 'Koyze');
    expect(header?.actions, hasLength(1));
  });

  testWidgets('pages and dialogs stay in the pane beside the side rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) =>
              IndependentSideRail(child: child ?? const SizedBox.shrink()),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const Text('right-popup'),
                );
              },
              child: const Text('open-popup'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Koyze'), findsOneWidget);
    final titleStyle = DefaultTextStyle.of(
      tester.element(find.text('Koyze')),
    ).style;
    expect(titleStyle.decoration, isNot(TextDecoration.underline));
    final rail = tester.getRect(find.text('Koyze'));
    await tester.tap(find.text('open-popup'));
    await tester.pumpAndSettle();

    final popup = tester.getCenter(find.text('right-popup'));
    expect(popup.dx, greaterThan(rail.right));
    expect(find.text('Koyze'), findsOneWidget);

    tester.view.physicalSize = const Size(400, 900);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Koyze'), findsNothing);
    expect(find.text('open-popup'), findsOneWidget);
  });
}

class _LayoutProbe extends StatelessWidget {
  const _LayoutProbe();

  @override
  Widget build(BuildContext context) {
    return Text(
      RootShellLayout.usesSideNavigationOf(context) ? 'side' : 'bottom',
    );
  }
}
