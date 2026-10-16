import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/card_expand.dart';
import 'package:koyze/core/widgets/pressable.dart';

void main() {
  testWidgets('Pressable captures its own card rect for expansion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 28,
              top: 72,
              width: 180,
              height: 64,
              child: Pressable(
                captureExpandRect: true,
                onTap: () {},
                child: const ColoredBox(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(Pressable));
    await tester.pump(const Duration(milliseconds: 110));
    final rect = consumeCardExpandRect();

    expect(rect, isNotNull);
    expect(rect!.left, closeTo(28, 0.1));
    expect(rect.top, closeTo(72, 0.1));
    expect(rect.width, closeTo(180, 0.1));
    expect(rect.height, closeTo(64, 0.1));
  });
}
