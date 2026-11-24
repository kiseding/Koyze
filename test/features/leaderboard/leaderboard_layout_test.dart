import 'package:flutter_test/flutter_test.dart';
import '../../support/source_text.dart';

/// 榜单页布局的护栏（方案 A：竖屏极简单列 / 横屏按平台三列）。
///
/// 这些结构一旦被改回去，就会退回「一进页面把几十个榜一次建完、并发几十个
/// 详情请求」，或者丢掉卡片展开转场。
void main() {
  final source = readSource('lib/features/leaderboard/presentation/leaderboard_screen.dart');

  test('竖屏用 SliverList 按行懒构建', () {
    final portrait = source.substring(
      source.indexOf('Widget _buildPortraitBrowse'),
      source.indexOf('List<LeaderboardCategory> _flattenCharts'),
    );
    // 只有按行懒构建，才会「建一行订阅一次 songs provider」；退回
    // SliverToBoxAdapter + Column 就是几十个榜同时发请求。
    expect(portrait, contains('SliverList.builder('));
    expect(portrait, isNot(contains('ref.watch(')));
    expect(source, isNot(contains('_buildSectionBody')));
    expect(source, isNot(contains('_buildChartRows')));
    expect(source, isNot(contains('SliverGrid(')));
  });

  test('分段被摊平成一串榜单', () {
    // 分组标题已经去掉：平台由吸顶的胶囊表示，列表里再挂一条「QQ音乐 ·
    // 8 个榜单」是把同一句话说第二遍。摊平后 SliverList 仍然只建可见行。
    expect(source, contains('List<LeaderboardCategory> _flattenCharts('));
    expect(source, isNot(contains('_BrowseRow')));
    expect(source, isNot(contains('_buildGroupLabel')));
  });

  test('平台胶囊钉住不随列表滚走', () {
    // 四五十行榜滚到底还想换平台，就得先滚回顶部——所以胶囊要走吸顶头。
    expect(source, contains('SliverPersistentHeader('));
    expect(source, contains('pinned: true'));
    expect(source, contains('class _PlatformTabsHeader'));
    // 留白必须由吸顶头自己带：单独一个 Spacer sliver 在前，吸顶头贴的是
    // 视口顶，会被状态栏和标题栏压住。
    expect(source, contains('topInset: FrostedTabHeader.extent(context)'));
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

  test('榜单数量写进各自的平台胶囊', () {
    // 以前数量在两处重复：顶部「8 个榜单」摘要、列表里的分组标题。
    // 现在只有胶囊里那个上标。
    expect(source, contains('Map<String, int> _chartCountByPlatform('));
    expect(source, contains('count: counts[platforms[index]] ?? 0'));
    expect(source, isNot(contains('S.of(context).chartCount(')));
  });

  test('胶囊吃未筛选的分段', () {
    // 传筛选后的分段只剩一个平台，platforms.length < 2 会把整条标签藏掉，
    // 用户再也切不到别的平台。
    expect(source, contains('platforms: _platformsOf(sections)'));
    expect(source, contains('counts: _chartCountByPlatform(sections)'));
  });

  test('筛选胶囊只有四个平台，没有「全部」', () {
    // 胶囊是四选一的单选：`allCharts`（全部）那颗已删除，文案也一并从
    // ARB 移除。若有人把它加回来，这里会先炸，而不是等用户发现多了一颗。
    expect(source, isNot(contains('allCharts')));
    expect(source, isNot(contains('MapEntry<String?, String>(null')));

    // 默认必须落到一个真实平台上：老实现用 `_platformFilter == null` 当
    // 「全部」，去掉胶囊后若不补默认值，首帧会四个平台全显示。
    expect(source, contains('String? _resolvePlatformFilter('));
    expect(source, contains('return platforms.first;'));

    // 平台整段消失时退回第一个平台，而不是退回全量——退回全量等于把
    // 「全部」偷偷复活。
    final filtered = source.substring(
      source.indexOf('List<_LeaderboardSection> _filteredSections('),
      source.indexOf('List<_LeaderboardSection> _groupByPlatform('),
    );
    expect(filtered, isNot(contains('matching.isEmpty ? sections')));
  });

  test('四个平台都出现在胶囊里', () {
    // 用户要的是四个平台各一颗胶囊。真正的平台 id 是 tx / kw / wy / kg
    // （见 tx_source.dart 等）；`qq` 只是 platformName 里的历史别名，没有任何
    // source 在用，钉它等于漏掉真实的那一个。
    final zh = readSource('lib/l10n/app_zh.arb');
    for (final key in [
      'platformName_tx',
      'platformName_kw',
      'platformName_wy',
      'platformName_kg',
    ]) {
      expect(zh, contains('"$key"'), reason: '缺少平台名 $key');
    }
  });
}
