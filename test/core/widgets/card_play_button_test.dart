import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/card_play_button.dart';

void main() {
  testWidgets('tap immediately triggers play and visible feedback', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardPlayButton(
            color: Colors.green,
            backgroundColor: Colors.greenAccent,
            onPressed: () => taps++,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('card-play-feedback-ring')),
          )
          .opacity,
      0,
    );

    await tester.tap(find.byType(CardPlayButton));
    await tester.pump();

    expect(taps, 1);
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('card-play-feedback-ring')),
          )
          .opacity,
      greaterThan(0),
    );

    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('card-play-feedback-ring')),
          )
          .opacity,
      0,
    );
  });

  testWidgets('disabled button does not trigger', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CardPlayButton(
            color: Colors.green,
            backgroundColor: Colors.greenAccent,
            onPressed: null,
            icon: Icon(Icons.play_arrow_rounded),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CardPlayButton));
    await tester.pump();

    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('card-play-feedback-ring')),
          )
          .opacity,
      0,
    );
  });
}
