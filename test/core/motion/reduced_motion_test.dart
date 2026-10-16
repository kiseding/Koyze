import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/animations/micro_animations.dart';
import 'package:koyze/core/motion/list_entrance.dart';

void main() {
  testWidgets('shared motion widgets use zero duration when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Column(
            children: [
              AnimatedIconSwitch(icon: Icons.play_arrow, keyValue: 'play'),
              ListEntrance(child: Text('row')),
            ],
          ),
        ),
      ),
    );

    expect(tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero);
    expect(
      tester
          .widget<TweenAnimationBuilder<double>>(
            find.byType(TweenAnimationBuilder<double>),
          )
          .duration,
      Duration.zero,
    );
  });
}
