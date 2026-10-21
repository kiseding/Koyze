import 'dart:async';
import 'dart:math';

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

const Map<String, String> kLeaderboardPlatformNames = {
  'tx': 'QQ音乐',
  'kw': '酷我音乐',
  'wy': '网易云',
};

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

  /// 竖屏的平台筛选；null 表示「全部」。
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
                            icon: Icons.tune_rounded,
                            semanticLabel: S.of(context).chartSettings,
                            onTap: () =>
                                context.push('/leaderboard-settings'),
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
    // 视口从磨砂顶栏下面开始：吸顶的平台标题才不会被顶栏盖住。代价是
    // 内容不再从顶栏底下钻过去，但这一页有吸顶条，留白换结构更划算。
    // 横屏没有顶栏，但要躲开状态栏，否则吸顶条会压在电量图标上。
    final topInset = isLandscapeShell
        ? 12 + MediaQuery.paddingOf(context).top
        : FrostedTabHeader.extent(context);
    // 侧栏模式（横屏 / 桌面）才用左右分栏，但窗口拉窄时两栏会互相挤，
    // 这时退回单列：左栏最窄也要 240，右栏再留 300 才装得下歌名。
    final useColumns = isLandscapeShell && contentWidth >= 560;
    return Padding(
      padding: EdgeInsets.only(top: topInset),
      child: useColumns
          ? _buildBrowseColumns(context, sections, contentWidth)
          : _buildPortraitBrowse(context, sections, contentWidth),
    );
  }

  /// 竖屏：方案 A 的极简单列。
  ///
  /// 顶栏标题由根壳层发布（26px「榜单」），页面内不再重复大标题，只留
  /// 一行 CHARTS 摘要 + 平台胶囊，避免同屏出现两个「榜单」。
  Widget _buildPortraitBrowse(
    BuildContext context,
    List<_LeaderboardSection> sections,
    double contentWidth,
  ) {
    final shown = _filteredSections(sections);
    final rows = _buildBrowseRows(shown);
    return CustomScrollView(
      // 用旧参数：CI 的 Flutter 3.44.9 与鸿蒙 fork 3.47.7 都要能编，
      // ScrollCacheExtent 只在 3.41+ 才有，跨版本时旧写法更保险。
      // ignore: deprecated_member_use
      cacheExtent: 400,
      slivers: [
        SliverToBoxAdapter(child: _buildChartsSummary(context, shown)),
        if (rows.isEmpty)
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final section = row.section;
                if (section != null) return _buildGroupLabel(context, section);
                final chart = row.chart!;
                return _LeaderboardChartTile(
                  category: chart,
                  platformColor: _platformColor(
                    context,
                    chart.platform ?? 'other',
                  ),
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

  /// 把分段摊平成一串「分组标题 / 榜单行」，交给 SliverList 懒构建。
  ///
  /// 让一行榜单决定「要不要拉详情」的是 [_LeaderboardChartTile] 自己的
  /// build，而 SliverList 只构建可见范围（含 cacheExtent），所以四十多个榜
  /// 不会一进页面就发四十多个请求——旧实现用 SliverToBoxAdapter + Column
  /// 一次性构建全段，正是那段注释里担心的场景。
  List<_BrowseRow> _buildBrowseRows(List<_LeaderboardSection> sections) {
    final rows = <_BrowseRow>[];
    for (final section in sections) {
      if (section.platform != null) rows.add(_BrowseRow.section(section));
      for (final chart in section.allCards) {
        rows.add(_BrowseRow.chart(chart));
      }
    }
    return rows;
  }

  /// 页面头部：CHARTS 小标 + 平台/榜单数量 + 平台胶囊。
  Widget _buildChartsSummary(
    BuildContext context,
    List<_LeaderboardSection> sections,
  ) {
    var total = 0;
    for (final section in sections) {
      total += section.chartCount;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CHARTS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.4,
                  color: AppColors.accentOf(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.of(context).chartSummary(sections.length, total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedText(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPlatformChips(context, sections),
        ],
      ),
    );
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
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
                  ),
                  Text(
                    S.of(context).chartSummary(shown.length, _totalCharts(shown)),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildPlatformChips(context, sections, dense: true),
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
                        platformColor: _platformColor(
                          context,
                          chart.platform ?? 'other',
                        ),
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

  int _totalCharts(List<_LeaderboardSection> sections) {
    var total = 0;
    for (final section in sections) {
      total += section.chartCount;
    }
    return total;
  }

  /// 平台筛选：方案 A 的圆角胶囊（选中实底反色）。只有一个平台时不出现。
  Widget _buildPlatformChips(
    BuildContext context,
    List<_LeaderboardSection> sections, {
    bool dense = false,
  }) {
    final platforms = <String>[];
    for (final section in sections) {
      final platform = section.platform;
      if (platform != null && !platforms.contains(platform)) {
        platforms.add(platform);
      }
    }
    if (platforms.length < 2) return const SizedBox.shrink();
    final filters = <MapEntry<String?, String>>[
      MapEntry<String?, String>(null, S.of(context).allCharts),
      for (final platform in platforms)
        MapEntry<String?, String>(platform, S.of(context).platformName(platform)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < filters.length; index++) ...[
            if (index > 0) SizedBox(width: dense ? 6 : 8),
            _buildChip(
              context,
              filters[index].value,
              _platformFilter == filters[index].key,
              () => setState(() => _platformFilter = filters[index].key),
              dense: dense,
            ),
          ],
        ],
      ),
    );
  }

  /// 单颗胶囊。未选中用主文字的 6% 做底——直接拿卡片色会和页面底色糊在一起。
  Widget _buildChip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap, {
    bool dense = false,
  }) {
    final onColor = AppColors.onScaffold(context);
    final background = selected
        ? onColor
        : onColor.withValues(alpha: 0.06);
    final foreground = selected
        ? AppColors.scaffold(context)
        : AppColors.secondaryText(context);
    return Pressable(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      selected: selected,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 14,
          vertical: dense ? 5 : 6,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: dense ? 10.5 : 12,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: foreground,
          ),
        ),
      ),
    );
  }

  /// 平台筛选后的分段；筛选到的平台整段消失了就退回全量，不留白屏。
  List<_LeaderboardSection> _filteredSections(
    List<_LeaderboardSection> sections,
  ) {
    final filter = _platformFilter;
    if (filter == null) return sections;
    final matching = <_LeaderboardSection>[
      for (final section in sections)
        if (section.platform == filter) section,
    ];
    return matching.isEmpty ? sections : matching;
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

  /// 竖屏分组标题：方案 A 的纯文字小标，靠上方留白和上一段分开。
  Widget _buildGroupLabel(BuildContext context, _LeaderboardSection section) {
    final platform = section.platform ?? 'other';
    final muted = AppColors.mutedText(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.of(context).platformName(platform),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: muted,
              ),
            ),
          ),
          if (section.chartCount > 0)
            Text(
              S.of(context).chartCount(section.chartCount),
              style: TextStyle(
                fontSize: 10,
                color: muted.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }

  /// 横屏列头：平台色点 + 名称 + 数量，底部一条细线（方案 A 的列头形态）。
  Widget _buildColumnHeader(
    BuildContext context,
    _LeaderboardSection section,
  ) {
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

  Color _platformColor(BuildContext context, String platform) {
    switch (platform) {
      case 'kw':
        return const Color(0xFF6B3FA0);
      case 'tx':
        return const Color(0xFF2355C0);
      case 'wy':
        return const Color(0xFF9B3060);
      default:
        return AppColors.accentOf(context);
    }
  }
}

/// 竖屏的一行榜单：封面 + 榜名 + 数量 + 前三首 + 播放键（方案 A 单列）。
///
/// 做成 ConsumerWidget 而不是在 SliverList.builder 的 itemBuilder 里
/// `ref.watch`——itemBuilder 是在布局阶段跑的，在那里注册依赖会被 Riverpod
/// 判成「build 之外改状态」。放进自己的 build 后还有个好处：只有真正被
/// 构建出来的行才订阅 songs provider，四十多个榜不会一进页面就全量请求。
class _LeaderboardChartTile extends ConsumerWidget {
  const _LeaderboardChartTile({
    required this.category,
    required this.platformColor,
    required this.onOpen,
    required this.onPlay,
  });

  final LeaderboardCategory category;
  final Color platformColor;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = category.platform ?? 'other';
    final songs = ref.watch(leaderboardSongsProvider(category.id)).valueOrNull;
    final songCount = songs?.length;
    final cover =
        category.coverUrl ??
        (songs != null && songs.isNotEmpty ? songs.first.artwork : null);
    final topSongs = songs == null
        ? const <MusicItem>[]
        : songs.take(3).toList(growable: false);
    final divider = AppColors.onScaffold(context).withValues(alpha: 0.07);
    final meta = songCount != null && songCount > 0
        ? '${S.of(context).platformName(platform)} · '
              '${S.of(context).songCount(songCount)}'
        : S.of(context).platformName(platform);
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
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      semanticLabel: category.name,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divider, width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      height: 1.2,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.2,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                  if (songLine != null) ...[
                    const SizedBox(height: 5),
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
              diameter: 32,
            ),
          ],
        ),
      ),
    );
  }
}

/// 横屏一列里的一行榜单：更紧凑，压在浅色块上（方案 A 的列内形态）。
class _LeaderboardChartCell extends ConsumerWidget {
  const _LeaderboardChartCell({
    required this.category,
    required this.platformColor,
    required this.onOpen,
    required this.onPlay,
  });

  final LeaderboardCategory category;
  final Color platformColor;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = category.platform ?? 'other';
    final songs = ref.watch(leaderboardSongsProvider(category.id)).valueOrNull;
    final songCount = songs?.length;
    final cover =
        category.coverUrl ??
        (songs != null && songs.isNotEmpty ? songs.first.artwork : null);
    final tint = AppColors.onScaffold(context).withValues(alpha: 0.035);
    final meta = songCount != null && songCount > 0
        ? S.of(context).songCount(songCount)
        : S.of(context).platformName(platform);

    return Pressable(
      captureExpandRect: true,
      borderRadius: BorderRadius.circular(10),
      onTap: onOpen,
      semanticLabel: category.name,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: 34,
                height: 34,
                child: cover != null && cover.isNotEmpty
                    ? ArtworkImage(
                        cover,
                        cacheWidth: 102,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _LeaderboardPlaceholder(
                          platform: platform,
                          name: category.name,
                          iconSize: 15,
                        ),
                      )
                    : _LeaderboardPlaceholder(
                        platform: platform,
                        name: category.name,
                        iconSize: 15,
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
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.2,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _TilePlayButton(
              category: category,
              onPressed: onPlay,
              diameter: 22,
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
    final background = isNowPlaying
        ? accent
        : onColor.withValues(alpha: 0.06);
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

/// 摊平后的一行：要么是平台分组标题，要么是一张榜。
class _BrowseRow {
  const _BrowseRow.section(this.section) : chart = null;
  const _BrowseRow.chart(this.chart) : section = null;

  final _LeaderboardSection? section;
  final LeaderboardCategory? chart;
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
