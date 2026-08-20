import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/play_pulse_button.dart';
import 'package:koyze/core/widgets/pressable.dart';
import 'package:koyze/core/widgets/fx_switch.dart';

void main() {
  testWidgets('Pressable exposes button state and activates from Enter', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Pressable(
            semanticLabel: '下一首',
            onTap: () => taps++,
            child: const Icon(Icons.skip_next),
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.bySemanticsLabel('下一首'));
    expect(semantics.flagsCollection.isButton, isTrue);
    await tester.tap(find.bySemanticsLabel('下一首'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 2);
  });

  testWidgets('play button reports toggled state and activates from Space', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayPulseButton(isPlaying: true, onPressed: () => taps++),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.bySemanticsLabel('暂停'));
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.flagsCollection.isToggled, Tristate.isTrue);
    await tester.tap(find.bySemanticsLabel('暂停'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 2);
  });

  testWidgets('FxSwitch is focusable, toggled, and keyboard activatable', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FxSwitch(
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );

    var semantics = tester.getSemantics(find.byType(FxSwitch));
    expect(semantics.flagsCollection.isEnabled, Tristate.isTrue);
    expect(semantics.flagsCollection.isToggled, Tristate.isFalse);

    await tester.tap(find.byType(FxSwitch));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(value, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(value, isTrue);
    semantics = tester.getSemantics(find.byType(FxSwitch));
    expect(semantics.flagsCollection.isToggled, Tristate.isTrue);
  });
}
