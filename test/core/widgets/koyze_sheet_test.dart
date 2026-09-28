import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/koyze_sheet.dart';

void main() {
  testWidgets('sheet max height stays below the status bar', (tester) async {
    late double height;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          padding: EdgeInsets.only(top: 59, bottom: 34),
          viewPadding: EdgeInsets.only(top: 59, bottom: 34),
        ),
        child: Builder(
          builder: (context) {
            height = koyzeSheetMaxHeight(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(height, 852 - 59 - 16);
  });

  testWidgets('sheet stays above the shell mini player', (tester) async {
    var sheetTaps = 0;
    var miniTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Navigator(
              onGenerateRoute: (settings) {
                return MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () {
                        showKoyzeSheet<void>(
                          context: context,
                          builder: (_) => SizedBox(
                            height: 240,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: TextButton(
                                onPressed: () => sheetTaps++,
                                child: const Text('sheet-bottom'),
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text('open-sheet'),
                    ),
                  ),
                );
              },
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 66,
                width: double.infinity,
                child: TextButton(
                  onPressed: () => miniTaps++,
                  child: const Text('mini-player'),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('sheet-bottom'));
    expect(sheetTaps, 1);
    expect(miniTaps, 0);
  });

  testWidgets('landscape option sheet scrolls instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(852, 393);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showKoyzeSheet<void>(
                context: context,
                builder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 8; i++)
                      SizedBox(
                        height: 56,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('option-$i'),
                        ),
                      ),
                  ],
                ),
              );
            },
            child: const Text('open-sheet'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('option-0'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('option-7'),
      80,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('option-7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
