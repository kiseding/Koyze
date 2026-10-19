import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 榜单页布局的护栏：这些结构一旦被改回去，滚到一半就不知道自己在哪个平台，
/// 或者几个平台的标题一起叠在顶上。
void main() {
  final source = File(
    'lib/features/leaderboard/presentation/leaderboard_screen.dart',
  ).readAsStringSync();

  test('each platform section is one sliver group', () {
    // 标题和它下面的网格必须在同一个 SliverMainAxisGroup 里：组的结束才会把
    // 吸顶状态推走，否则每个段的标题都会一直贴在顶上。
    expect(source, contains('SliverMainAxisGroup('));
    expect(source, contains('pinned: true'));
  });

  test('the list is a sliver grid, not rows of hand-built Columns', () {
    expect(source, contains('SliverGrid('));
    expect(source, contains('childAspectRatio: 3 / 2'));
    expect(source, isNot(contains('_packLeaderboardRows')));
  });

  test('platform header shows how many charts are in the block', () {
    expect(source, contains('S.of(context).chartCount('));
  });
}
