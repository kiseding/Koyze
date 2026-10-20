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

  test('the section body is one adapter, cards first then text rows', () {
    // 辅卡只剩编号和榜名，整段一次建完；不要退回 SliverGrid 那种封面格子，
    // 一屏只放得下 8 个榜、封面还各说各话。
    expect(source, contains('SliverToBoxAdapter('));
    expect(source, isNot(contains('SliverGrid(')));
    expect(source, isNot(contains('childAspectRatio: 3 / 2')));
    expect(source, isNot(contains('_packLeaderboardRows')));
    // 主卡必须渲染在辅卡行之前，否则段首就不是「这个平台的正榜」。
    expect(
      source.indexOf('_buildHeroRow(context, hero)'),
      lessThan(source.indexOf('_buildChartRows(')),
    );
  });

  test('the three canonical charts all get a card', () {
    // 三个平台都有这三个榜，所以它们是固定的，不是「找到哪个算哪个」。
    expect(source, contains('const List<String> kHeroChartNames'));
    expect(source, contains("'热歌榜'"));
    expect(source, contains("'新歌榜'"));
    expect(source, contains("'飙升榜'"));
    // 必须精确比对：酷我还有 抖音热歌榜 / 网红新歌榜 / ACG新歌榜。
    expect(source, isNot(contains('contains(kHeroChartNames')));
  });

  test('platform header shows how many charts are in the block', () {
    expect(source, contains('S.of(context).chartCount('));
  });
}
