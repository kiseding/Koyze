import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/root_shell_layout.dart';

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

  test('landscape safe areas do not collapse the side rail', () {
    const horizontalInset = EdgeInsets.symmetric(horizontal: 59);
    expect(
      sideNavigationWidth(
        enabled: true,
        padding: horizontalInset,
        viewPadding: horizontalInset,
      ),
      235,
    );
    expect(
      sideNavigationWidth(
        enabled: false,
        padding: horizontalInset,
        viewPadding: horizontalInset,
      ),
      0,
    );
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
