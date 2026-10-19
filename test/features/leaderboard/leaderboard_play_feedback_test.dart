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

    expect(button, contains('CardPlayButton('));
    expect(button, contains('size: diameter'));
    // 按钮直径 40：卡片高度只有 ~113，54 的圆会盖掉近一半封面。
    expect(button, contains('const diameter = 40.0'));
    expect(button, contains('onPressed: onPressed'));

    expect(source, contains('leaderboardId: category.id'));
    expect(
      source,
      isNot(contains('service.nowPlayingLeaderboardId = category.id')),
    );
  });
}
