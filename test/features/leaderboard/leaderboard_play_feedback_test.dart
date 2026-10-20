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
    // 直径是一个参数：主卡行高 68，用 34；默认 40。原来是写死的局部 const，
    // 结果辅卡和主卡只能共用一个尺寸。
    expect(button, contains('this.diameter = 40'));
    expect(button, contains('onPressed: onPressed'));
    expect(source, contains('diameter: 34'));

    expect(source, contains('leaderboardId: category.id'));
    expect(
      source,
      isNot(contains('service.nowPlayingLeaderboardId = category.id')),
    );
  });
}
