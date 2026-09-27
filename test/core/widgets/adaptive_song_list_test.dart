import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/adaptive_song_list.dart';

void main() {
  testWidgets('landscape song list lays out two columns row by row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSongList.builder(
            itemCount: 4,
            itemBuilder: (context, index) => Text('song-$index'),
          ),
        ),
      ),
    );

    expect(find.byType(GridView), findsOneWidget);
    final first = tester.getTopLeft(find.text('song-0'));
    final second = tester.getTopLeft(find.text('song-1'));
    final third = tester.getTopLeft(find.text('song-2'));
    expect(first.dx, lessThan(second.dx));
    expect(first.dy, closeTo(second.dy, 0.1));
    expect(third.dy, greaterThan(first.dy));
  });

  testWidgets('portrait song list remains a single column', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSongList.builder(
            itemCount: 2,
            itemBuilder: (context, index) => Text('song-$index'),
          ),
        ),
      ),
    );

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  test('recommendation page no longer builds the orange banner', () {
    final source = File(
      'lib/features/recommend/presentation/recommendation_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('Widget _buildHeader(')));
    expect(
      source,
      isNot(contains('_buildHeader(context, recommendations.length)')),
    );
  });
}
