import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_strings.dart';
import '../../../core/music_source/platform/music_platform.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/adaptive_song_list.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/card_play_button.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/frosted_tab_header.dart';
import '../../../core/widgets/root_shell_layout.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../core/widgets/pressable.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import 'leaderboard_provider.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/glass_config.dart';
import '../../../core/theme/platform_colors.dart';
import 'leaderboard_settings_screen.dart';

/// 每个平台段里挑出来当主卡的榜。
///
/// 三个平台都有这三个榜，而且名字完全一致，所以只能精确比对：酷我另有
/// 「抖音热歌榜」「网红新歌榜」「ACG新歌榜」，用 contains 会把它们也认成主卡。
///
/// 这三个也是这一页唯一会被反复回访的榜，其余大多是一次性浏览，压成小卡就够。
/// 列表顺序即展示顺序，热歌榜固定第一行——它比另两个更常被点。
const List<String> kHeroChartNames = ['热歌榜', '新歌榜', '飙升榜'];

/// 榜单页：固定 QQ、酷我、网易云平台顺序，支持隐藏平台/榜单。
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  bool _layoutScheduled = false;

  /// 当前选中的平台。
  ///
  /// 曾经可空，`null` 代表「全部」并额外渲染一颗同名胶囊。那颗胶囊去掉后
  /// 筛选变成了四选一的单选：没有「不筛选」这个状态，进页面必然停在一个
  /// 平台上。空值仍保留，仅表示「还没初始化」——首帧的真实平台列表还没
  /// 算出来，由 [_resolvePlatformFilter] 落成第一个平台。
  String? _platformFilter;

  /// 默认布局要等当前帧建完才能生成：它内部会写 provider 状态，在 build
  /// 期间写会被 Riverpod 拦下来（清数据后首次进入必现红屏）。
  void _scheduleDefaultLayout(List<LeaderboardCategory> categories) {
    if (_layoutScheduled) return;
    _layoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (!mounted) return;
      ref
          .read(leaderboardLayoutProvider.notifier)
          .ensureDefaultLayout(categories);
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(leaderboardCategoriesProvider);
    ref.watch(leaderboardLayoutProvider);

    // 按布局过滤出可见/隐藏
    final categoryByKey = <String, LeaderboardCategory>{};
    for (final category
        in categoriesAsync.valueOrNull ?? const <LeaderboardCategory>[]) {
      categoryByKey['category:${category.id}'] = category;
    }

    final isLandscapeShell = RootShellLayout.usesSideNavigationOf(context);
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 底部安全区已由 MainScaffold（底栏+迷你栏）处理。
        // 顶部不包 SafeArea：磨砂要铺到屏幕顶（含灵动岛/状态栏）。
        body: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = shellContentWidth(constraints.maxWidth);

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: categoriesAsync.when(
                        loading: () => Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: AppLoadingIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.accentOf(context),
                              ),
                            ),
                          ),
                        ),
                        error: (error, _) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppColors.error,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${S.of(context).loadSongsFailed}: $error',
                                style: TextStyle(
                                  color: AppColors.secondaryText(context),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => ref.invalidate(
                                  leaderboardCategoriesProvider,
                                ),
                                child: Text(S.of(context).retry),
                              ),
                            ],
                          ),
                        ),
                        data: (categories) {
                          if (categories.isEmpty) {
                            return Center(
                              child: Text(
                                S.of(context).noChartData,
                                style: TextStyle(
                                  color: AppColors.mutedText(context),
                                ),
                              ),
                            );
                          }
                          // 首次进入时还没有本地布局。生成默认布局会改 provider
                          // 状态，不能在 build 期间做——清空数据后第一次打开这
                          // 一页，Riverpod 会抛「Tried to modify a provider
                          // while the widget tree was building」并整页红屏。
                          // 放到这一帧结束之后再生成，当前帧先显示加载态。
                          final layout = ref.watch(leaderboardLayoutProvider);
                          if (layout.isEmpty) {
                            _scheduleDefaultLayout(categories);
                            return Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: AppLoadingIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.accentOf(context),
                                  ),
                                ),
                              ),
                            );
                          }
                          final visible = <LeaderboardLayoutItem>[];
                          for (final item in layout) {
                            if (!item.hidden) visible.add(item);
                          }

                          if (visible.isEmpty) {
                            return Center(
                              child: Text(
                                S.of(context).chartsHidden,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.mutedText(context),
                                ),
                              ),
                            );
                          }
                          return _buildLeaderboardList(
                            context,
                            visible,
                            categoryByKey,
                            contentWidth,
                            isLandscapeShell,
                          );
                        },
                      ),
                    ),
                    // 只发布标题：顶栏由根壳层渲染，切 tab 时不会跟着页面走。
                    Positioned(
                      left: 0,
                      top: 0,
                      width: 0,
                      height: 0,
                      child: RootHeaderPublisher(
                        index: 1,
                        title: S.of(context).charts,
                        actions: [
                          FrostedHeaderButton(
                            // 首页的 hero 设置用的是 tune；这一页换成
                            // 自定义仪表盘，两个 tab 的右上角不再撞图标。
                            icon: Icons.dashboard_customize_rounded,
                            semanticLabel: S.of(context).chartSettings,
                            onTap: () => showLeaderboardSettingsSheet(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 方案 A「极简列表」：竖屏单列按平台分段，横屏按平台三列并排。
  Widget _buildLeaderboardList(
    BuildContext context,
    List<LeaderboardLayoutItem> visible,
    Map<String, LeaderboardCategory> categoryByKey,
    double contentWidth,
    bool isLandscapeShell,
  ) {
    final sections = _groupByPlatform(visible, categoryByKey);
    // 侧栏模式（横屏 / 桌面）才用左右分栏，但窗口拉窄时两栏会互相挤，
    // 这时退回单列：左栏最窄也要 240，右栏再留 300 才装得下歌名。
    final useColumns = isLandscapeShell && contentWidth >= 560;
    if (useColumns) {
      // 横屏 / 桌面走左栏，没有顶部标题栏，只需躲开状态栏。
      return Padding(
        padding: EdgeInsets.only(top: 12 + MediaQuery.paddingOf(context).top),
        child: _buildBrowseColumns(context, sections, contentWidth),
      );
    }
    // 竖屏：**不要**在这一层套 top padding。
    //
    // 早先这里包了 `Padding(top: 顶栏高度)`，滚动视口整个被推到标题栏下沿，
    // 内容裁在自己的盒子里，永远到不了栏背后——栏背后只剩一块纯色页面底，
    // 而「模糊一层纯色」和「什么都不做」在屏幕上是同一个像素。表现就是「四
    // 个 tab 页里只有设置页看得到磨砂」：设置页把留白写在 ListView 的
    // padding 里，视口从屏幕顶开始，内容才会从栏背后穿过。
    // 现在留白改由 sliver 承担（见 [_buildPortraitBrowse]），视口回到 y=0。
    return _buildPortraitBrowse(context, sections, contentWidth);
  }

  /// 竖屏：方案 B 的极简单列。
  ///
  /// 顶栏标题由根壳层发布（26px「榜单」），页面内不再重复大标题，也不再写
  /// 「CHARTS / N 个榜单」——榜单数量已经进了各自的平台胶囊，列表里那条
  /// 「QQ音乐 · 8 个榜单」分组标题同样多余：胶囊选中的就是那一家，再说一遍
  /// 只是把同一句话说三次。
  Widget _buildPortraitBrowse(
    BuildContext context,
    List<_LeaderboardSection> sections,
    double contentWidth,
  ) {
    final shown = _filteredSections(sections);
    final charts = _flattenCharts(shown);
    final platforms = _platformsOf(sections);
    final counts = _chartCountByPlatform(sections);
    final selected = _resolvePlatformFilter(platforms);
    return CustomScrollView(
      // 用旧参数：CI 的 Flutter 3.44.9 与鸿蒙 fork 3.47.7 都要能编，
      // ScrollCacheExtent 只在 3.41+ 才有，跨版本时旧写法更保险。
      // ignore: deprecated_member_use
      cacheExtent: 400,
      slivers: [
        // 让出根壳层标题栏的高度，但**写成 sliver 而不是外层 Padding**：
        // 视口必须从屏幕顶开始，滚起来的内容才会从栏背后穿过，栏上的磨砂
        // 才有东西可糊。写成外层 Padding 的话滚动视口被压到栏下沿，内容
        // 永远到不了栏背后，磨砂看起来就是「没生效」。
        //
        // 平台胶囊吸在这段留白下面（见 [_PlatformTabsHeader]），所以留白改由
        // 吸顶头自己带：写成两个 sliver 的话，吸顶头贴的是视口顶，会被状态栏
        // 和标题栏压住。
        if (platforms.length < 2)
          SliverToBoxAdapter(
            child: SizedBox(height: FrostedTabHeader.extent(context)),
          )
        else
          SliverPersistentHeader(
            pinned: true,
            delegate: _PlatformTabsHeader(
              topInset: FrostedTabHeader.extent(context),
              platforms: platforms,
              counts: counts,
              selected: selected,
              onSelect: (platform) =>
                  setState(() => _platformFilter = platform),
            ),
          ),
        if (charts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                S.of(context).chartsHidden,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.mutedText(context)),
              ),
            ),
          )
        else
          SliverPadding(
            // 顶部只留 2：胶囊下沿自带 8 的间距，再给 12 会空出一条断层。
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            sliver: SliverList.builder(
              itemCount: charts.length,
              itemBuilder: (context, index) {
                final chart = charts[index];
                return _LeaderboardChartTile(
                  category: chart,
                  onOpen: () => _openCategory(context, chart),
                  onPlay: () => _playLeaderboard(ref, chart),
                );
              },
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 20 + RootShellLayout.obscuredBottomOf(context),
          ),
        ),
      ],
    );
  }

  /// 把分段摊平成一串榜单，交给 SliverList 懒构建。
  ///
  /// 让一行榜单决定「要不要拉详情」的是 [_LeaderboardChartTile] 自己的
  /// build，而 SliverList 只构建可见范围（含 cacheExtent），所以四十多个榜
  /// 不会一进页面就发四十多个请求——旧实现用 SliverToBoxAdapter + Column
  /// 一次性构建全段，正是那段注释里担心的场景。
  List<LeaderboardCategory> _flattenCharts(List<_LeaderboardSection> sections) {
    return [for (final section in sections) ...section.allCards];
  }

  /// 每个平台有多少个榜。按平台累加而不是取第一条：布局里同一个平台被
  /// 拆成两段时（用户手动排过序），总数要是两段之和。
  Map<String, int> _chartCountByPlatform(List<_LeaderboardSection> sections) {
    final counts = <String, int>{};
    for (final section in sections) {
      final platform = section.platform;
      if (platform == null) continue;
      counts[platform] = (counts[platform] ?? 0) + section.chartCount;
    }
    return counts;
  }

  /// 横屏：方案 A 的三列并排，一列一个平台。
  ///
  /// 横屏没有磨砂顶栏，所以这里补完整的 CHARTS / 榜单头部；竖屏那个
  /// 大标题由根壳层负责，两处不重复。
  Widget _buildBrowseColumns(
    BuildContext context,
    List<_LeaderboardSection> sections,
    double contentWidth,
  ) {
    final shown = _filteredSections(sections);
    if (shown.isEmpty) {
      return Center(
        child: Text(
          S.of(context).chartsHidden,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mutedText(context)),
        ),
      );
    }
    // 三列是方案 A 的目标形态；窗口窄到装不下时降两列、再降单列，
    // 宁可少一列也不要把榜名挤成省略号。
    final maxColumns = contentWidth >= 700 ? 3 : (contentWidth >= 460 ? 2 : 1);
    final visible = shown.length > maxColumns
        ? shown.sublist(0, maxColumns)
        : shown;
    final divider = AppColors.onScaffold(context).withValues(alpha: 0.07);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 数量不再单独占一行：四家各有多少个榜已经写进下面的胶囊里，
              // 这里再报一遍总数只是把同一件事说两次。
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CHARTS',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                      color: AppColors.accentOf(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    S.of(context).charts,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_platformsOf(sections).length >= 2)
                _platformTabsRow(
                  context,
                  platforms: _platformsOf(sections),
                  counts: _chartCountByPlatform(sections),
                  selected: _resolvePlatformFilter(_platformsOf(sections)),
                  dense: true,
                  onSelect: (platform) =>
                      setState(() => _platformFilter = platform),
                ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < visible.length; index++) ...[
                if (index > 0) Container(width: 0.5, color: divider),
                Expanded(child: _buildPlatformColumn(context, visible[index])),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 横屏的一列：列头（平台色点 + 名称 + 数量）+ 该平台的榜单列表。
  Widget _buildPlatformColumn(
    BuildContext context,
    _LeaderboardSection section,
  ) {
    final charts = section.allCards;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: _buildColumnHeader(context, section),
        ),
        Expanded(
          child: charts.isEmpty
              ? Center(
                  child: Text(
                    S.of(context).noChartData,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(
                    left: 10,
                    right: 10,
                    bottom: 10 + RootShellLayout.obscuredBottomOf(context),
                  ),
                  itemCount: charts.length,
                  itemBuilder: (context, index) {
                    final chart = charts[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _LeaderboardChartCell(
                        category: chart,
                        onOpen: () => _openCategory(context, chart),
                        onPlay: () => _playLeaderboard(ref, chart),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 分段里出现过的平台，按首次出现顺序（即用户排好的顺序）。
  List<String> _platformsOf(List<_LeaderboardSection> sections) {
    final platforms = <String>[];
    for (final section in sections) {
      final platform = section.platform;
      if (platform != null && !platforms.contains(platform)) {
        platforms.add(platform);
      }
    }
    return platforms;
  }

  /// 把筛选落到一个真实存在的平台上。
  ///
  /// 默认取第一个平台：胶囊去掉「全部」后没有「不筛选」这个状态，进页面
  /// 必须停在一个平台上。用户选中的平台若因为设置里被隐藏而消失，也退回
  /// 第一个——否则整页会空掉，用户还以为数据没了。
  String? _resolvePlatformFilter(List<String> platforms) {
    if (platforms.isEmpty) return null;
    final current = _platformFilter;
    if (current != null && platforms.contains(current)) return current;
    return platforms.first;
  }

  /// 平台筛选后的分段。
  ///
  /// 恒停在一个平台上：没有「全部」，所以这里不再有「返回全量」的分支。
  /// 选中的平台整段消失（用户在设置里隐藏了它）时退回第一个平台，而不是
  /// 返回全量——返回全量会让四个平台一起冒出来，和刚去掉的「全部」等价。
  List<_LeaderboardSection> _filteredSections(
    List<_LeaderboardSection> sections,
  ) {
    final filter = _resolvePlatformFilter(_platformsOf(sections));
    if (filter == null) return sections;
    final matching = <_LeaderboardSection>[
      for (final section in sections)
        if (section.platform == filter) section,
    ];
    return matching;
  }

  /// 按平台切段：平台标题卡出一个新段，段内是这一平台的全部榜单。
  /// 段头可能为 null（第一个榜单之前没有平台标题），此时不吸顶。
  List<_LeaderboardSection> _groupByPlatform(
    List<LeaderboardLayoutItem> visible,
    Map<String, LeaderboardCategory> categoryByKey,
  ) {
    final sections = <_LeaderboardSection>[];
    LeaderboardLayoutItem? header;
    var cards = <LeaderboardCategory>[];

    void flush() {
      // 只剩平台头也要留着这一段：某个平台的分类没拿到时，宁可显示一个空段，
      // 也不要让整个平台凭空消失——用户会以为设置里丢了他的榜单。
      if (cards.isNotEmpty || header != null) {
        // 段里精确叫「热歌榜 / 新歌榜 / 飙升榜」的三个当主卡，按
        // kHeroChartNames 的顺序排，其余保持用户排好的顺序。
        // 用户隐藏了某一个、或者平台以后改了名，就少那一行——不要拿别的榜
        // 顶替，否则「段首这几张」的含义就不成立了。
        final heroes = <LeaderboardCategory>[];
        for (final name in kHeroChartNames) {
          for (final card in cards) {
            if (card.name == name) {
              heroes.add(card);
              break;
            }
          }
        }
        final heroIds = {for (final hero in heroes) hero.id};
        final rest = cards
            .where((card) => !heroIds.contains(card.id))
            .toList(growable: false);
        sections.add(
          _LeaderboardSection(header: header, heroes: heroes, cards: rest),
        );
      }
      cards = <LeaderboardCategory>[];
      header = null;
    }

    for (final item in visible) {
      if (item.isPlatform) {
        flush();
        header = item;
        continue;
      }
      final category = categoryByKey[item.key];
      if (category != null) cards.add(category);
    }
    flush();
    return sections;
  }

  /// 横屏列头：平台色点 + 名称 + 数量，底部一条细线。
  Widget _buildColumnHeader(BuildContext context, _LeaderboardSection section) {
    final platform = section.platform ?? 'other';
    final divider = AppColors.onScaffold(context).withValues(alpha: 0.07);
    return Container(
      padding: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _platformColor(context, platform),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              S.of(context).platformName(platform),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: AppColors.onScaffold(context),
              ),
            ),
          ),
          if (section.chartCount > 0)
            Text(
              '${section.chartCount}',
              style: TextStyle(
                fontSize: 9.5,
                color: AppColors.mutedText(context),
              ),
            ),
        ],
      ),
    );
  }

  void _openCategory(BuildContext context, LeaderboardCategory category) {
    context.push(
      '/leaderboard/detail?id=${Uri.encodeComponent(category.id)}'
      '&name=${Uri.encodeComponent(category.name)}',
    );
  }

  Future<void> _playLeaderboard(
    WidgetRef ref,
    LeaderboardCategory category,
  ) async {
    try {
      // 等待榜单歌曲加载完成再播放，避免首次点击时缓存为空而静默失败。
      final songs = await ref.read(
        leaderboardSongsProvider(category.id).future,
      );
      if (songs.isEmpty) return;
      final service = ref.read(playerServiceProvider);
      unawaited(
        service.setQueue(
          songs,
          startIndex: 0,
          manualPlayName: songs.first.name,
          leaderboardId: category.id,
        ),
      );
    } catch (error) {
      // 播放失败由 PlayerMessageListener 统一提示。
    }
  }

  /// 平台品牌色集中在 [platformBrandColor] 里，榜单设置与导入弹窗共用
  /// 同一份取值，换色不会只改到其中一页。
  Color _platformColor(BuildContext context, String platform) =>
      platformBrandColor(context, platform);
}

/// 榜单卡的底色，与「歌单」页 `_PresetCard`（OrigoChromeSurface → chrome 档）
/// 完全同一层。
///
/// 为什么不直接用那个 widget：它会挂一层 BackdropFilter，列表里同时可见
/// 十几张卡就是十几层全宽实时模糊。卡下面只有页面底色、没有内容穿过去，
/// 模糊本来也看不出差别——这里直接按 chrome 档的染色透明度把底色合成到
/// 页面底色上，出图一致、开销为零。
///
/// 别改用 `GlassSurface` 的 `blur: 0` 分支：那条路把透明度强制成 0.94
/// （低内存模式的兜底），比歌单卡实一档，颜色就差了两个色阶。
Color _leaderboardCardFill(BuildContext context) => Color.alphaBlend(
  AppGlass.fillColor(context, style: AppGlassStyle.chrome),
  AppColors.scaffold(context),
);

/// 竖屏的一行榜单：封面 + 榜名 + 数量 + 前三首 + 播放键（方案 A 单列）。
///
/// 做成 ConsumerWidget 而不是在 SliverList.builder 的 itemBuilder 里
/// `ref.watch`——itemBuilder 是在布局阶段跑的，在那里注册依赖会被 Riverpod
/// 判成「build 之外改状态」。放进自己的 build 后还有个好处：只有真正被
/// 构建出来的行才订阅 songs provider，四十多个榜不会一进页面就全量请求。
class _LeaderboardChartTile extends ConsumerWidget {
  const _LeaderboardChartTile({
    required this.category,
    required this.onOpen,
    required this.onPlay,
  });

  final LeaderboardCategory category;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = category.platform ?? 'other';
    final songs = ref.watch(leaderboardSongsProvider(category.id)).valueOrNull;
    // 与其他平台保持一致：优先用榜首歌曲的封面，没有时再退回榜单自带封面。
    final cover =
        (songs != null && songs.isNotEmpty ? songs.first.artwork : null) ??
        category.coverUrl;
    final topSongs = songs == null
        ? const <MusicItem>[]
        : songs.take(3).toList(growable: false);
    final songLine = topSongs.isEmpty
        ? null
        : [
            for (var index = 0; index < topSongs.length; index++)
              '${index + 1} ${topSongs[index].name}',
          ].join('   ');

    return Pressable(
      // 与首页、设置页同一套卡片展开转场：记下这一行的屏幕矩形，
      // 详情页由 expandablePage 做矩形 morph，关闭时沿原路收拢回来。
      captureExpandRect: true,
      // 卡片规格对齐「歌单」页的 _PresetCard：圆角 18、内边距 12、
      // 封面 48 圆角 14、标题 14.5。两个 tab 来回切时同一条目不该有两种
      // 行高、两种字号，更不该有两种底色。
      borderRadius: BorderRadius.circular(18),
      onTap: onOpen,
      semanticLabel: category.name,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _leaderboardCardFill(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.fromBorderSide(AppGlass.hairline(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: cover != null && cover.isNotEmpty
                      ? ArtworkImage(
                          cover,
                          cacheWidth: 144,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _LeaderboardPlaceholder(
                            platform: platform,
                            name: category.name,
                            iconSize: 20,
                          ),
                        )
                      : _LeaderboardPlaceholder(
                          platform: platform,
                          name: category.name,
                          iconSize: 20,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        height: 1.2,
                        color: AppColors.onScaffold(context),
                      ),
                    ),
                    // 副标题（平台 · 榜单数量）已经去掉：平台在分组标题里
                    // 写着，数量对听众没有决策价值，留白只给榜名和前三首。
                    if (songLine != null) ...[
                      // 8 而不是 5：去掉副标题后两行贴得太紧，榜名和歌曲挤成
                      // 一块。卡片高度由 48 的封面决定（两行文字加起来 38），
                      // 加 3 也不会把行撑高。
                      const SizedBox(height: 8),
                      Text(
                        songLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: AppColors.secondaryText(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _TilePlayButton(
                category: category,
                onPressed: onPlay,
                diameter: 38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 横屏一列里的一行榜单：更紧凑，压在浅色块上（方案 A 的列内形态）。
class _LeaderboardChartCell extends ConsumerWidget {
  const _LeaderboardChartCell({
    required this.category,
    required this.onOpen,
    required this.onPlay,
  });

  final LeaderboardCategory category;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = category.platform ?? 'other';
    final songs = ref.watch(leaderboardSongsProvider(category.id)).valueOrNull;
    // 与其他平台保持一致：优先用榜首歌曲的封面，没有时再退回榜单自带封面。
    final cover =
        (songs != null && songs.isNotEmpty ? songs.first.artwork : null) ??
        category.coverUrl;
    // 与竖屏卡一致：只有榜名和前三首，不留平台 / 数量这类副标题。
    final topSongs = songs == null
        ? const <MusicItem>[]
        : songs.take(3).toList(growable: false);
    final songLine = topSongs.isEmpty
        ? null
        : [for (final song in topSongs) song.name].join(' · ');

    return Pressable(
      captureExpandRect: true,
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      semanticLabel: category.name,
      // 和竖屏卡、歌单卡同一层底色，只是按列内尺寸收了一档。
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: _leaderboardCardFill(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.fromBorderSide(AppGlass.hairline(context)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 36,
                height: 36,
                child: cover != null && cover.isNotEmpty
                    ? ArtworkImage(
                        cover,
                        cacheWidth: 108,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _LeaderboardPlaceholder(
                          platform: platform,
                          name: category.name,
                          iconSize: 16,
                        ),
                      )
                    : _LeaderboardPlaceholder(
                        platform: platform,
                        name: category.name,
                        iconSize: 16,
                      ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  if (songLine != null) ...[
                    // 同竖屏卡：两行之间留一口气，别挤成一块。列内是紧凑
                    // 档，收到 4。
                    const SizedBox(height: 4),
                    Text(
                      songLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.2,
                        color: AppColors.mutedText(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            _TilePlayButton(
              category: category,
              onPressed: onPlay,
              diameter: 26,
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表行上的播放键。
///
/// 不复用 [_LeaderboardPlayButton]：那个带 BackdropFilter，卡片形态只有三张
/// 时无所谓，铺成四十几行就是四十几层实时模糊。这里用纯色圆底，正在播放时
/// 换成强调色 + 旋转音符，状态语义与卡片版一致。
class _TilePlayButton extends ConsumerWidget {
  const _TilePlayButton({
    required this.category,
    required this.onPressed,
    required this.diameter,
  });

  final LeaderboardCategory category;
  final VoidCallback onPressed;
  final double diameter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNowPlaying = ref.watch(
      currentMusicProvider.select((music) {
        final service = ref.read(playerServiceProvider);
        return music != null && service.nowPlayingLeaderboardId == category.id;
      }),
    );
    final onColor = AppColors.onScaffold(context);
    final accent = AppColors.accentOf(context);
    final background = isNowPlaying ? accent : onColor.withValues(alpha: 0.06);
    final iconColor = isNowPlaying ? Colors.white : onColor;
    return CardPlayButton(
      size: diameter,
      tooltip: isNowPlaying
          ? S.of(context).nowPlayingNamed(category.name)
          : S.of(context).playNamed(category.name),
      color: iconColor,
      backgroundColor: background,
      onPressed: onPressed,
      icon: isNowPlaying
          ? _NowPlayingSpin(
              child: Icon(
                Icons.music_note,
                color: Colors.white,
                size: diameter * 0.62,
              ),
            )
          : Icon(
              Icons.play_arrow_rounded,
              color: iconColor,
              size: diameter * 0.78,
            ),
    );
  }
}

/// 一排平台胶囊，选中那颗就是当前平台。
///
/// 数量写进胶囊里（`QQ音乐 8`），所以页面不再需要「8 个榜单」那行摘要，
/// 也不再需要在列表里重复一遍分组标题。
///
/// 顶层函数而不是 `_LeaderboardScreenState` 的方法：吸顶头
/// （[_PlatformTabsHeader]）要在一个没有 state 引用的地方重建这排胶囊。
Widget _platformTabsRow(
  BuildContext context, {
  required List<String> platforms,
  required Map<String, int> counts,
  required String? selected,
  required ValueChanged<String> onSelect,
  bool dense = false,
}) {
  return Row(
    children: [
      for (var index = 0; index < platforms.length; index++) ...[
        if (index > 0) const SizedBox(width: 6),
        // 等分而不是按内容宽：四颗在 360dp 上也放得下，不需要横向滑动。
        Expanded(
          child: _PlatformTab(
            key: ValueKey('platform-tab-${platforms[index]}'),
            platform: platforms[index],
            label: S.of(context).platformName(platforms[index]),
            count: counts[platforms[index]] ?? 0,
            selected: selected == platforms[index],
            dense: dense,
            onTap: () => onSelect(platforms[index]),
          ),
        ),
      ],
    ],
  );
}

/// 一颗平台胶囊：选中＝该平台品牌玻璃底，未选中＝透明底 + 品牌色细边。
///
/// 未选中不铺底色，只保留轮廓，让四颗胶囊仍然清晰可辨，同时把视觉焦点
/// 留给当前平台。
///
/// 选中态的白字对比度由 [platformBrandFill] 保证（≥ 4.5:1）——品牌原色
/// 直接铺白字，QQ 绿和酷我黄是读不出来的。
class _PlatformTab extends StatelessWidget {
  const _PlatformTab({
    super.key,
    required this.platform,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  final String platform;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // 不透明度和虚化是全局信号，改了不会让这一页重建——这里直接听，拖动
    // 设置里的滑杆时胶囊当帧跟着变。
    return ListenableBuilder(
      listenable: Listenable.merge([
        GlassEffectConfig.surfaceOpacityListenable,
        GlassEffectConfig.surfaceBlurListenable,
      ]),
      builder: (context, _) => _buildPill(context),
    );
  }

  Widget _buildPill(BuildContext context) {
    final fill = platformBrandFill(platform);
    final hue = platformBrandHue(platform);
    // 玻璃三件套全部来自设置：染色浓度是「界面不透明度」，背后采样按
    // 「虚化」缩放，和导航栏、迷你播放器同一套。
    final alpha = GlassEffectConfig.surfaceAlpha;
    final sigma = GlassEffectConfig.userBlurEnabled
        ? GlassEffectConfig.scaleSurfaceBlur(
            AppGlass.blurFor(AppGlassStyle.regular),
          )
        : 0.0;
    final tint = fill.withValues(alpha: alpha);
    final onTint = _textOnTint(context, tint);

    return Pressable(
      borderRadius: BorderRadius.circular(999),
      selected: selected,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: dense ? 30 : 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          // 未选中也保留轻量品牌边缘；底色仍完全透明。
          border: selected
              ? null
              : Border.all(color: hue.withValues(alpha: 0.42), width: 1),
          // 光晕用的是品牌原色而不是压深后的填充色：填充色做投影只是一圈
          // 灰影，原色才看得出「这是哪一家」。原色在这里不承担文字对比。
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: hue.withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              // 未选中不铺任何底色：四颗都带色底会平均分掉视线，只让当前
              // 那一颗亮起来，"现在在哪一家"才是第一眼看到的。
              if (selected) ...[
                if (sigma > 0)
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                      child: const SizedBox.expand(),
                    ),
                  ),
                Positioned.fill(child: ColoredBox(color: tint)),
                // 淡到几乎看不见时，靠一圈同色发丝边把形状留住——玻璃面
                // 在别处也都有这条边。
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: hue.withValues(alpha: 0.32),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  // 四颗等分 320dp 的宽度，英文平台名（QQ Music / NetEase）
                  // 比中文长，真放不下时整颗等比缩一点，不要截断成「QQ Mus…」。
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: dense ? 11 : 12.5,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            letterSpacing: -0.3,
                            height: 1.2,
                            color: selected
                                ? onTint
                                : AppColors.secondaryText(context),
                          ),
                        ),
                        const SizedBox(width: 3),
                        // 数量当上标：它是标签的注脚，不该和平台名一样重。
                        Transform.translate(
                          offset: const Offset(0, -3),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: dense ? 9 : 9.5,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              letterSpacing: 0,
                              color: selected
                                  ? onTint
                                  : AppColors.mutedText(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 胶囊上的字色。
  ///
  /// 玻璃是半透明的，白色压不压得住取决于「染色层盖在什么上面」，而这里
  /// 唯一确定的衬底是页面底色：浅色主题下最亮、深色主题下最暗，其中浅色
  /// 是白字最危险的那一侧（65% 的琥珀压在白底上只有 2.5:1）。所以拿页面
  /// 底色算一遍：白字够 4.5 就用白字，不够就退回同色系的深色——浅色主题
  /// 下胶囊是「淡色底 + 品牌深字」，深色主题下仍是「品牌底 + 白字」。
  Color _textOnTint(BuildContext context, Color tint) {
    final blended = Color.alphaBlend(tint, AppColors.scaffold(context));
    final white = 1.05 / (blended.computeLuminance() + 0.05);
    if (white >= 4.5) return Colors.white;
    return Color.lerp(platformBrandFill(platform), Colors.black, 0.62)!;
  }
}

/// 吸顶的平台胶囊条。
///
/// 为什么不用 `SliverToBoxAdapter`：榜单有四五十行，滚到下半屏时想换平台
/// 得先滚回顶部。钉住之后随时能切。
///
/// [topInset] 是磨砂标题栏的高度，条子必须留出这一段再把胶囊画在下面：
/// 直接贴视口顶会被状态栏和「榜单」标题压住。那一段留白保持透明，标题栏
/// 的磨砂才照得到从背后滚过的内容（画成实色会把磨砂毁掉）。
///
/// 胶囊条的背景复用顶部 tab 栏的磨砂玻璃，滚动内容穿过时仍能保持文字可读；
/// 上方标题栏留白不加第二层玻璃，避免和根壳层的磨砂重复采样。
class _PlatformTabsHeader extends SliverPersistentHeaderDelegate {
  const _PlatformTabsHeader({
    required this.topInset,
    required this.platforms,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final double topInset;
  final List<String> platforms;
  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String> onSelect;

  static const double _stripHeight = 34;
  static const EdgeInsets _stripPadding = EdgeInsets.fromLTRB(20, 10, 20, 8);

  @override
  double get minExtent => topInset + _stripHeight + _stripPadding.vertical;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Column(
      children: [
        SizedBox(height: topInset),
        SizedBox(
          height: _stripHeight + _stripPadding.vertical,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GradientAppBarBackground(
                background: Theme.of(context).scaffoldBackgroundColor,
                child: const SizedBox.expand(),
              ),
              Padding(
                padding: _stripPadding,
                child: _platformTabsRow(
                  context,
                  platforms: platforms,
                  counts: counts,
                  selected: selected,
                  onSelect: onSelect,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _PlatformTabsHeader old) {
    return old.topInset != topInset ||
        old.selected != selected ||
        old.platforms.length != platforms.length ||
        old.counts.length != counts.length;
  }
}

/// 一个平台段：平台标题（可能为 null）+ 该平台的主卡 + 其余榜单的辅卡。
class _LeaderboardSection {
  const _LeaderboardSection({
    required this.header,
    required this.cards,
    this.heroes = const <LeaderboardCategory>[],
  });

  final LeaderboardLayoutItem? header;

  /// 段首主卡（热歌榜 / 新歌榜 / 飙升榜），按 [kHeroChartNames] 的顺序，
  /// 缺哪个就少一行。空列表时这一段只有辅卡。
  final List<LeaderboardCategory> heroes;

  /// 辅卡，已排除 [heroes]。
  final List<LeaderboardCategory> cards;

  /// 这一段实际展示的榜单总数，含主卡。
  int get chartCount => cards.length + heroes.length;

  /// 目录型布局（横屏左栏）用的完整列表：主榜在前，其余按用户排好的顺序。
  List<LeaderboardCategory> get allCards => [...heroes, ...cards];

  /// 布局项的平台标识；`null` 段没有标题，不会吸顶。
  String? get platform => header?.platformId;
}

/// 封面加载失败或无封面时的渐变占位。
class _LeaderboardPlaceholder extends StatelessWidget {
  final String platform;
  final String name;
  final double iconSize;

  const _LeaderboardPlaceholder({
    required this.platform,
    required this.name,
    this.iconSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    final seed = _hashString(platform + name);
    final random = Random(seed);
    final palette = _palette(platform);
    final baseColor = palette[seed % palette.length];
    final accentColor = palette[(seed + 1) % palette.length];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(
            random.nextDouble() * 2 - 1,
            random.nextDouble() * 2 - 1,
          ),
          end: Alignment(
            random.nextDouble() * 2 - 1,
            random.nextDouble() * 2 - 1,
          ),
          colors: [baseColor, accentColor],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.leaderboard,
          color: Colors.white.withAlpha(220),
          size: iconSize,
        ),
      ),
    );
  }

  List<Color> _palette(String platform) {
    switch (platform) {
      case 'kw':
        return const [Color(0xFF6B3FA0), Color(0xFF9B59B6), Color(0xFF8E44AD)];
      case 'tx':
        return const [Color(0xFF2355C0), Color(0xFF3498DB), Color(0xFF2980B9)];
      case 'wy':
        return const [Color(0xFF9B3060), Color(0xFFE74C3C), Color(0xFFC0392B)];
      case 'kg':
        return const [Color(0xFF2B7CD3), Color(0xFF4AA8E8), Color(0xFF1F66B8)];
      default:
        return const [Color(0xFF3D4A5A), Color(0xFF5D6D7E)];
    }
  }

  static int _hashString(String input) {
    var hash = 0;
    for (final code in input.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }
}

/// 正在播放的榜单按钮：音符持续旋转（4s/圈），营造"正在播放"的灵动感。
class _NowPlayingSpin extends StatefulWidget {
  const _NowPlayingSpin({required this.child});

  final Widget child;

  @override
  State<_NowPlayingSpin> createState() => _NowPlayingSpinState();
}

class _NowPlayingSpinState extends State<_NowPlayingSpin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.maybeOf(context)?.accessibleNavigation == true) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(turns: _controller, child: widget.child);
  }
}

/// 通过 ID 和名称显示的排行榜详情页（用于路由）
class LeaderboardDetailScreenById extends ConsumerWidget {
  final String id;
  final String name;
  const LeaderboardDetailScreenById({
    super.key,
    required this.id,
    required this.name,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(leaderboardSongsProvider(id));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 列表可滚动到栏内部（栏高度不变），顶栏磨砂才可见。
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          // 顶栏整栏磨砂玻璃，无底部渐变透明。
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          title: Text(
            name,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.onScaffold(context),
            ),
          ),
        ),
        body: songsAsync.when(
          loading: () => Center(
            child: AppLoadingIndicator(color: AppColors.accentOf(context)),
          ),
          error: (e, _) => Center(
            child: Text(
              '${S.of(context).loadSongsFailed}: $e',
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
          data: (songs) {
            if (songs.isEmpty) {
              return Center(
                child: Text(
                  S.of(context).noSongData,
                  style: TextStyle(color: AppColors.mutedText(context)),
                ),
              );
            }
            return AdaptiveSongList.builder(
              cacheExtent: 420,
              landscapeItemExtent: 82,
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              itemCount: songs.length,
              itemBuilder: (context, index) => _LeaderboardSongRow(
                song: songs[index],
                index: index,
                onTap: () {
                  ref
                      .read(playerServiceProvider)
                      .setQueue(
                        songs,
                        startIndex: index,
                        manualPlayName: songs[index].name,
                      );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LeaderboardSongRow extends ConsumerWidget {
  const _LeaderboardSongRow({
    required this.song,
    required this.index,
    required this.onTap,
  });

  final MusicItem song;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 共享的收藏集合由 favoriteIdsProvider 缓存，行内直接查 Set。
    final favoriteSongs =
        ref.watch(favoriteSongsProvider).valueOrNull ?? const <MusicItem>[];
    final isPlaying = ref.watch(
      currentMusicProvider.select(
        (current) => current?.identityKey == song.identityKey,
      ),
    );
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassSurface(
          style: AppGlassStyle.regular,
          borderRadius: BorderRadius.circular(16),
          // 每行都在同一块纯白页面底上，模糊前后是同一个颜色。榜单能有上百行，
          // 一屏可见十来行——不改这一处，滚动时每帧要白跑十几次背景采样。
          //
          // solidBehind 是必须的：只写 backdrop: false 时，虚化档一开（出厂
          // 即开）这些行又会重新采样，而这正是「引入虚化后滑动掉帧」的来源。
          backdrop: false,
          solidBehind: true,
          border: Border.fromBorderSide(
            AppGlass.hairline(context, emphasized: false),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: isPlaying
                        ? Icon(
                            Icons.play_arrow,
                            size: 22,
                            color: AppColors.accentOf(context),
                          )
                        : Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: index < 3
                                  ? AppColors.accentOf(context)
                                  : AppColors.mutedText(context),
                              fontSize: 14,
                              fontWeight: index < 3
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder(context)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: song.artwork != null && song.artwork!.isNotEmpty
                          ? ArtworkImage(
                              song.artwork!,
                              cacheWidth: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.music_note,
                                color: AppColors.mutedText(context),
                                size: 20,
                              ),
                            )
                          : Icon(
                              Icons.music_note,
                              color: AppColors.mutedText(context),
                              size: 20,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.name,
                          style: TextStyle(
                            color: isPlaying
                                ? AppColors.accentOf(context)
                                : AppColors.onScaffold(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.singer,
                          style: TextStyle(
                            color: AppColors.mutedText(context),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  FavoriteButton(
                    song: song,
                    isFavorite: isFavoriteMusic(song, favoriteSongs),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
