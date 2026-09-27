import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/presentation/widgets/player_volume_button.dart';

void main() {
  Future<void> open(WidgetTester tester, {required bool horizontal}) async {
    tester.view.physicalSize = horizontal
        ? const Size(900, 400)
        : const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: PlayerVolumeButton(horizontal: horizontal)),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PlayerVolumeButton));
    await tester.pumpAndSettle();
  }

  testWidgets('portrait volume panel stays vertical', (tester) async {
    await open(tester, horizontal: false);

    final track = tester.getSize(
      find.byKey(const Key('volume-track-vertical')),
    );
    expect(track.height, greaterThan(track.width));
    expect(find.byKey(const Key('volume-track-horizontal')), findsNothing);
  });

  testWidgets('landscape volume panel opens sideways', (tester) async {
    await open(tester, horizontal: true);

    final track = tester.getSize(
      find.byKey(const Key('volume-track-horizontal')),
    );
    expect(track.width, greaterThan(track.height));
    expect(find.byKey(const Key('volume-track-vertical')), findsNothing);
  });
}
