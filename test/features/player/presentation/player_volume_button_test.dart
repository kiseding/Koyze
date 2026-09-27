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
    expect(track.width, lessThanOrEqualTo(100));
    expect(track.height, lessThanOrEqualTo(24));
    expect(find.byKey(const Key('volume-track-vertical')), findsNothing);

    final panel = tester.getRect(find.byKey(const Key('volume-panel')));
    final button = tester.getRect(find.byType(PlayerVolumeButton));
    expect(panel.height, lessThan(40));
    expect(panel.width, lessThan(180));
    expect(panel.bottom, lessThanOrEqualTo(button.top + 1));
    expect(panel.right, closeTo(button.right, 8));
  });
}
