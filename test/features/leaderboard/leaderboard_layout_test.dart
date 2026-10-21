import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 榜单页布局的护栏（方案 A：竖屏极简单列 / 横屏按平台三列）。
///
/// 这些结构一旦被改回去，就会退回「一进页面把几十个榜一次建完、并发几十个
/// 详情请求」，或者丢掉卡片展开转场。
void main() {
  final source = File(
    'lib/features/leaderboard/presentation/leaderboard_screen.dart',
  ).readAsStringSync();

  test('竖屏用 SliverList 按行懒构建', () {
    final portrait = source.substring(
      source.indexOf('Widget _buildPortraitBrowse'),
      source.indexOf('List<_BrowseRow> _buildBrowseRows'),
    );
    // 只有按行懒构建，才会「建一行订阅一次 songs provider」；退回
    // SliverToBoxAdapter + Column 就是几十个榜同时发请求。
    expect(portrait, contains('SliverList.builder('));
    expect(portrait, isNot(contains('ref.watch(')));
    expect(source, isNot(contains('_buildSectionBody')));
    expect(source, isNot(contains('_buildChartRows')));
    expect(source, isNot(contains('SliverGrid(')));
  });

  test('分段被摊平成「分组标题 + 榜单行」的序列', () {
    expect(source, contains('List<_BrowseRow> _buildBrowseRows('));
    expect(source, contains('_BrowseRow.section('));
    expect(source, contains('_BrowseRow.chart('));
  });

  test('榜单行自身是 ConsumerWidget，订阅发生在自己的 build 里', () {
    // itemBuilder 是在布局阶段跑的，在那里 ref.watch 会被 Riverpod 判成
    // 「build 之外改状态」，所以订阅必须落在行自己的 build。
    final tile = source.substring(
      source.indexOf('class _LeaderboardChartTile'),
      source.indexOf('class _LeaderboardChartCell'),
    );
    expect(tile, contains('extends ConsumerWidget'));
    expect(tile, contains('ref.watch(leaderboardSongsProvider'));
  });

  test('榜单行走与首页同一套卡片展开转场', () {
    // 详情页由 expandablePage 做矩形 morph，行必须先把自身矩形交出去，
    // 否则打开/关闭会退化成普通页面转场。
    expect(source, contains('captureExpandRect: true'));
    expect(source, contains('class _LeaderboardChartTile'));
    expect(source, contains('class _LeaderboardChartCell'));
  });

  test('横屏按平台分列，不再是左目录 + 右歌曲面板', () {
    // 左目录 + 右面板会把「浏览所有平台」和「看某个榜的歌」挤在同一屏，
    // 前者才是榜单页的职责，后者交给详情页。
    expect(source, contains('Widget _buildPlatformColumn('));
    expect(source, isNot(contains('_buildChartDirectory')));
    expect(source, isNot(contains('_buildChartPane')));
  });

  test('the three canonical charts still lead each section', () {
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

  test('平台胶囊吃未筛选的分段', () {
    // 传 shown 的话，选中某个平台后只剩一个平台，_buildPlatformChips 里的
    // platforms.length < 2 会把整条标签藏掉，用户再也切不回「全部」。
    expect(source, contains('_buildChartsSummary(context, sections)'));
  });
}
