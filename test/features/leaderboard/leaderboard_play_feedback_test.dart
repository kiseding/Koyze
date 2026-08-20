import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leaderboard cards use immediate animated play feedback', () {
    final source = File(
      'lib/features/leaderboard/presentation/leaderboard_screen.dart',
    ).readAsStringSync();
    final button = source.substring(
      source.indexOf('class _LeaderboardPlayButton'),
      source.indexOf('class LeaderboardDetailScreenById'),
    );

    expect(button, contains('return CardPlayButton('));
    expect(button, contains('onPressed: onPressed'));
  });
}
