import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/fx_switch.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness inactive track can contrast with its card', (
      tester,
    ) async {
      final inactive = brightness == Brightness.dark
          ? const Color(0xFF2C2C2E)
          : const Color(0xFFE5E5EA);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: FxSwitch(
              value: false,
              inactiveTrackColor: inactive,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final track = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .single;
      final decoration = track.decoration! as BoxDecoration;
      expect(decoration.color, inactive);
    });
  }
}
