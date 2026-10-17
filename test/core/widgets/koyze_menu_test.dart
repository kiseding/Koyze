import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/koyze_menu.dart';

Widget _host({
  required ValueChanged<String> onSelected,
  bool disableAnimations = false,
}) {
  return MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      size: const Size(390, 844),
    ),
    child: MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            KoyzePopupMenuButton<String>(
              key: const ValueKey('menu-trigger'),
              onSelected: onSelected,
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'one',
                  child: Text('First action'),
                ),
                const PopupMenuItem<String>(
                  value: 'two',
                  child: Text('Second action'),
                ),
              ],
            ),
          ],
        ),
        body: const SizedBox.expand(),
      ),
    ),
  );
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-trigger')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('anchored menu keeps a floating width and screen margin', (
    tester,
  ) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(onSelected: (_) {}));
    await _openMenu(tester);

    final surface = tester.getRect(
      find.byKey(const ValueKey('koyze-menu-morph-surface')),
    );
    expect(surface.width, 272);
    expect(surface.left, greaterThanOrEqualTo(12));
    expect(surface.right, lessThanOrEqualTo(390 - 12));
    expect(find.text('First action'), findsOneWidget);
  });

  testWidgets('anchored menu returns the selected PopupMenuItem value', (
    tester,
  ) async {
    _setViewport(tester);
    String? selected;
    await tester.pumpWidget(_host(onSelected: (value) => selected = value));
    await _openMenu(tester);

    await tester.tap(find.text('Second action'));
    await tester.pumpAndSettle();

    expect(selected, 'two');
    expect(find.text('Second action'), findsNothing);
  });

  testWidgets('escape dismisses the anchored menu', (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(onSelected: (_) {}));
    await _openMenu(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('koyze-menu-morph-surface')),
      findsNothing,
    );
    expect(find.text('First action'), findsNothing);
  });

  testWidgets('reduced motion opens and closes without a lingering route', (
    tester,
  ) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(onSelected: (_) {}, disableAnimations: true));
    await _openMenu(tester);
    expect(find.text('First action'), findsOneWidget);

    await tester.tapAt(const Offset(24, 400));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('koyze-menu-morph-surface')),
      findsNothing,
    );
  });
}
