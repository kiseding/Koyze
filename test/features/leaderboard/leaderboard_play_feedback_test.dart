import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/leaderboard/presentation/leaderboard_screen.dart',
  ).readAsStringSync();

  test('列表行用轻量播放键', () {
    final button = source.substring(
      source.indexOf('class _TilePlayButton'),
      source.indexOf('class _BrowseRow'),
    );
    expect(button, contains('CardPlayButton('));
    expect(button, contains('size: diameter'));
    expect(button, contains('onPressed: onPressed'));
    expect(button, contains('nowPlayingLeaderboardId == category.id'));
    // 行内播放键不能再挂 BackdropFilter：卡片形态只有三张时无所谓，
    // 铺成四十几行就是四十几层实时模糊。
    expect(button, isNot(contains('BackdropFilter')));
  });

  test('竖屏与横屏各用各的直径', () {
    // 竖屏 38（对齐歌单卡的播放键）、横屏 26（三列窄栏）：两个尺寸都得从
    // 外面传进去，不能写死在组件里。
    expect(source, contains('diameter: 38'));
    expect(source, contains('diameter: 26'));
  });

  test('播放走完整榜单队列，不是单曲', () {
    expect(source, contains('leaderboardId: category.id'));
    expect(
      source,
      isNot(contains('service.nowPlayingLeaderboardId = category.id')),
    );
  });
}
