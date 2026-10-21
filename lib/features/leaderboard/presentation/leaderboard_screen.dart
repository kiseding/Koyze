import 'dart:async';
import 'dart:math';
import 'dart:ui';

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

  /// 横屏右栏里正在看的榜；null 时用第一段的第一张榜。
  String? _selectedCategoryId;

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
                              Icon(
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

  /// 平台标题条：34 是内容高度，后面 12 是渐隐，内容从它下面穿过去。
  static const double _headerExtent = 46;
  static const double _headerContentExtent = 34;

  static const double _rowGap = 14;
  static const double _chartRowHeight = 34;

  /// 主榜卡片：148 宽，封面占 132，剩下 16 给左右内边距。
  static const double _cardWidth = 148;
  static const double _cardGap = 10;

  /// 窄屏两列、宽屏三列。辅卡只剩榜名，210 以上放长榜名才不用省略号。
  static int _columnsFor(double contentWidth) => contentWidth >= 520 ? 3 : 2;

  /// 方案 1「双轴浏览」：竖屏纵向按平台分段、段内榜单横向滑动；
  /// 横屏左栏平台 + 榜单目录、右栏选中榜单的歌曲。
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

  /// 竖屏：平台筛选 + 一列分段的自定义滚动区。
  Widget _buildPortraitBrowse(
    BuildContext context,
    List<_LeaderboardSection> sections,
    double contentWidth,
  ) {
    final shown = _filteredSections(sections);
    final columns = _columnsFor(contentWidth);
    final tabs = _buildPlatformTabs(context, sections);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tabs != null) tabs,
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    S.of(context).chartsHidden,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.mutedText(context)),
                  ),
                )
              : CustomScrollView(
                  cacheExtent: 520,
                  slivers: [
                    for (final section in shown)
                      // 每个平台是一个 sliver 组：组的结束会把组头的吸顶状态
                      // 一起推走，否则每个段的标题都会一直叠在顶上。
                      SliverMainAxisGroup(
                        slivers: [
                          if (section.platform != null)
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _PlatformHeaderDelegate(
                                extent: _headerExtent,
                                contentExtent: _headerContentExtent,
                                background:
                                    Theme.of(context).scaffoldBackgroundColor,
                                child: _buildPlatformHeader(context, section),
                              ),
                            )
                          else
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 8),
                            ),
                          SliverToBoxAdapter(
                            child: _buildSectionBody(
                              context,
                              section,
                              columns,
                            ),
                          ),
                        ],
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 16 + RootShellLayout.obscuredBottomOf(context),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// 横屏：左目录、右歌曲。左栏固定宽度，右栏吃掉剩下的空间。
  Widget _buildBrowseColumns(
    BuildContext context,
    List<_LeaderboardSection> sections,
    double contentWidth,
  ) {
    final shown = _filteredSections(sections);
    final selected = _selectedCategory(shown);
    final leftWidth = (contentWidth * 0.42).clamp(240.0, 320.0).toDouble();
    final divider = AppColors.onScaffold(context).withValues(alpha: 0.07);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: leftWidth,
          child: _buildChartDirectory(context, shown, selected),
        ),
        Container(width: 0.5, color: divider),
        Expanded(child: _buildChartPane(context, selected)),
      ],
    );
  }

  /// 平台筛选条：全部 + 每个平台一档。只有一个平台时整条不出现。
  Widget? _buildPlatformTabs(
    BuildContext context,
    List<_LeaderboardSection> sections,
  ) {
    final platforms = <String>[];
    for (final section in sections) {
      final platform = section.platform;
      if (platform != null && !platforms.contains(platform)) {
        platforms.add(platform);
      }
    }
    if (platforms.length < 2) return null;
    final divider = AppColors.onScaffold(context).withValues(alpha: 0.07);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _buildFilterTab(
              context,
              S.of(context).allCharts,
              _platformFilter == null,
              () {
                if (_platformFilter != null) {
                  setState(() => _platformFilter = null);
                }
              },
            ),
            for (final platform in platforms)
              _buildFilterTab(
                context,
                S.of(context).platformName(platform),
                _platformFilter == platform,
                () => setState(
                  () => _platformFilter = _platformFilter == platform
                      ? null
                      : platform,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final color = selected
        ? AppColors.onScaffold(context)
        : AppColors.mutedText(context);
    return Pressable(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      selected: selected,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected
                  ? AppColors.onScaffold(context)
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.1,
            color: color,
          ),
        ),
      ),
    );
  }

  /// 一段的正文：主榜卡片横向滑动，其余榜单仍是两列文字行。
  ///
  /// 整段只给三张主榜拉封面：卡片里要放前三首歌，每张卡都要读一次榜单详情。
  /// 酷我一共有四十多个榜，全铺成卡片就是四十多次请求，横向滑到底也很难
  /// 找到想要的那个——主榜之外继续用纯文字行。
  Widget _buildSectionBody(
    BuildContext context,
    _LeaderboardSection section,
    int columns,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (section.heroes.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final hero in section.heroes) ...[
                  _buildHeroRow(context, hero),
                  const SizedBox(width: _cardGap),
                ],
              ],
            ),
          ),
        if (section.cards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildChartRows(
                context,
                section.cards,
                columns,
                section.heroes.length + 1,
              ),
            ),
          )
        else
          const SizedBox(height: 6),
      ],
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

  /// 辅卡排成等宽列。编号是「这一段里的第几个」，按阅读顺序从左到右数，
  /// 不是榜单名次——名次是详情页里那 100 首歌的事。编号接着上面的主卡往下走
  /// （三张主卡占 01..03），否则第一行辅卡又从 01 开始，会读成榜首。
  List<Widget> _buildChartRows(
    BuildContext context,
    List<LeaderboardCategory> cards,
    int columns,
    int firstOrdinal,
  ) {
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += columns) {
      final cells = <Widget>[];
      for (var column = 0; column < columns; column++) {
        if (column > 0) cells.add(const SizedBox(width: _rowGap));
        final index = i + column;
        cells.add(
          Expanded(
            child: index < cards.length
                ? _buildChartCell(context, cards[index], firstOrdinal + index)
                : const SizedBox.shrink(),
          ),
        );
      }
      rows.add(Row(children: cells));
    }
    return rows;
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

  /// 平台标题：吸顶时也要能盖住下面滚上来的封面，所以是实底 + 末尾渐隐，
  /// 不用 BackdropFilter（滚动中每帧重新采样太贵）。
  Widget _buildPlatformHeader(
    BuildContext context,
    _LeaderboardSection section,
  ) {
    final platform = section.platform ?? 'other';
    final name = S.of(context).platformName(platform);
    final color = _platformColor(context, platform);
    return Row(
      children: [
        // 段头只留一个色点：平台色是这一页唯一的颜色来源，方块加图标
        // 会和下面的热歌榜行抢注意力。
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: AppColors.onScaffold(context),
          ),
        ),
        const Spacer(),
        if (section.chartCount > 0)
          Text(
            S.of(context).chartCount(section.chartCount),
            style: TextStyle(fontSize: 11, color: AppColors.mutedText(context)),
          ),
      ],
    );
  }

  void _openCategory(BuildContext context, LeaderboardCategory category) {
    context.push(
      '/leaderboard/detail?id=${Uri.encodeComponent(category.id)}'
      '&name=${Uri.encodeComponent(category.name)}',
    );
  }

  /// 主榜卡片：封面 + 榜名 + 前三首歌，横向排成一条。
  ///
  /// 只有热歌榜 / 新歌榜 / 飙升榜进这条卡片带：卡片要读榜单详情拿前三首，
  /// 让四十多个榜都进带子就是四十多次请求，横着滑到底也没人找得到。
  Widget _buildHeroRow(BuildContext context, LeaderboardCategory category) {
    final platform = category.platform ?? 'other';
    final color = _platformColor(context, platform);
    final isDark = AppColors.isDark(context);
    // 首歌数来自已有的 provider：加载完就有，没加载完就不显示，
    // 不拿「每日更新」这种编出来的文案占位。
    final songs = ref.watch(leaderboardSongsProvider(category.id)).valueOrNull;
    final songCount = songs?.length;
    // 分类接口不再逐榜拉封面，卡片封面直接取榜单首曲的封面。
    final cover =
        category.coverUrl ??
        (songs != null && songs.isNotEmpty ? songs.first.artwork : null);
    final topSongs = songs == null
        ? const <MusicItem>[]
        : songs.take(3).toList(growable: false);
    return Pressable(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openCategory(context, category),
      child: Container(
        width: _cardWidth,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.34 : 0.16),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: SizedBox(
                width: _cardWidth - 16,
                height: _cardWidth - 16,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null && cover.isNotEmpty)
                      ArtworkImage(
                        cover,
                        cacheWidth: 320,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _LeaderboardPlaceholder(
                          platform: platform,
                          name: category.name,
                          iconSize: 30,
                        ),
                      )
                    else
                      _LeaderboardPlaceholder(
                        platform: platform,
                        name: category.name,
                        iconSize: 30,
                      ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: _LeaderboardPlayButton(
                        category: category,
                        diameter: 34,
                        onPressed: () => _playLeaderboard(ref, category),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                height: 1.2,
                color: AppColors.onScaffold(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              songCount != null && songCount > 0
                  ? S.of(context).songCount(songCount)
                  : S.of(context).platformName(platform),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.mutedText(context),
              ),
            ),
            if (topSongs.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (var index = 0; index < topSongs.length; index++)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 11,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: index == 0
                                ? AppColors.onScaffold(context)
                                : AppColors.mutedText(context),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          topSongs[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.3,
                            color: AppColors.secondaryText(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 横屏右栏要显示哪一张榜：优先用户点过的，否则第一个平台的第一张榜。
  LeaderboardCategory? _selectedCategory(
    List<_LeaderboardSection> sections,
  ) {
    final wanted = _selectedCategoryId;
    if (wanted != null) {
      for (final section in sections) {
        for (final category in section.allCards) {
          if (category.id == wanted) return category;
        }
      }
    }
    for (final section in sections) {
      for (final category in section.allCards) {
        return category;
      }
    }
    return null;
  }

  /// 横屏左栏：平台分组 + 榜单目录。
  ///
  /// 目录里不读榜单详情，只认分类接口带的封面：一整列四十多项如果每项都
  /// watch 一次 songs provider，进页面就是四十多个并发请求。
  Widget _buildChartDirectory(
    BuildContext context,
    List<_LeaderboardSection> sections,
    LeaderboardCategory? selected,
  ) {
    final rows = <Widget>[];
    for (final section in sections) {
      final platform = section.platform;
      if (platform != null) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _platformColor(context, platform),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    S.of(context).platformName(platform),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                ),
                if (section.chartCount > 0)
                  Text(
                    S.of(context).chartCount(section.chartCount),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.mutedText(context),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
      for (final category in section.allCards) {
        rows.add(
          _buildDirectoryTile(
            context,
            category,
            selected != null && category.id == selected.id,
          ),
        );
      }
    }
    return ListView(
      padding: EdgeInsets.only(
        bottom: 16 + RootShellLayout.obscuredBottomOf(context),
      ),
      children: rows,
    );
  }

  Widget _buildDirectoryTile(
    BuildContext context,
    LeaderboardCategory category,
    bool selected,
  ) {
    final platform = category.platform ?? 'other';
    final color = _platformColor(context, platform);
    final isDark = AppColors.isDark(context);
    final cover = category.coverUrl;
    return Pressable(
      borderRadius: BorderRadius.circular(10),
      selected: selected,
      onTap: () => setState(() => _selectedCategoryId = category.id),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 1, 8, 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: isDark ? 0.22 : 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 34,
                height: 34,
                child: cover != null && cover.isNotEmpty
                    ? ArtworkImage(
                        cover,
                        cacheWidth: 120,
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
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  height: 1.25,
                  color: AppColors.onScaffold(context),
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 横屏右栏：选中榜的头部 + 歌曲列表。
  Widget _buildChartPane(
    BuildContext context,
    LeaderboardCategory? category,
  ) {
    if (category == null) {
      return Center(
        child: Text(
          S.of(context).noChartData,
          style: TextStyle(color: AppColors.mutedText(context)),
        ),
      );
    }
    final platform = category.platform ?? 'other';
    final songsAsync = ref.watch(leaderboardSongsProvider(category.id));
    final songs = songsAsync.valueOrNull;
    final songCount = songs?.length;
    final cover =
        category.coverUrl ??
        (songs != null && songs.isNotEmpty ? songs.first.artwork : null);
    final subtitle = songCount != null && songCount > 0
        ? '${S.of(context).platformName(platform)} · '
              '${S.of(context).songCount(songCount)}'
        : S.of(context).platformName(platform);
    final divider = AppColors.onScaffold(context).withValues(alpha: 0.07);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: cover != null && cover.isNotEmpty
                      ? ArtworkImage(
                          cover,
                          cacheWidth: 180,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _LeaderboardPlaceholder(
                                platform: platform,
                                name: category.name,
                                iconSize: 22,
                              ),
                        )
                      : _LeaderboardPlaceholder(
                          platform: platform,
                          name: category.name,
                          iconSize: 22,
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
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.15,
                        color: AppColors.onScaffold(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _LeaderboardPlayButton(
                category: category,
                diameter: 40,
                onPressed: () => _playLeaderboard(ref, category),
              ),
            ],
          ),
        ),
        Container(height: 0.5, color: divider),
        Expanded(
          child: songsAsync.when(
            loading: () => Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: AppLoadingIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.accentOf(context),
                  ),
                ),
              ),
            ),
            error: (error, _) => Center(
              child: Text(
                '${S.of(context).loadSongsFailed}: $error',
                style: TextStyle(color: AppColors.mutedText(context)),
              ),
            ),
            data: (loaded) {
              if (loaded.isEmpty) {
                return Center(
                  child: Text(
                    S.of(context).noSongData,
                    style: TextStyle(color: AppColors.mutedText(context)),
                  ),
                );
              }
              return ListView.builder(
                itemCount: loaded.length,
                itemExtent: 58,
                padding: EdgeInsets.only(
                  bottom: 12 + RootShellLayout.obscuredBottomOf(context),
                ),
                itemBuilder: (context, index) => _ChartPaneSongRow(
                  songs: loaded,
                  index: index,
                  categoryId: category.id,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 辅卡：一整行只有编号和榜名。封面缩到这个尺寸以后既认不出内容，
  /// 又要为每张图留 10pt 内边距，不如干脆不要。
  Widget _buildChartCell(
    BuildContext context,
    LeaderboardCategory category,
    int ordinal,
  ) {
    final platform = category.platform ?? 'other';
    final color = _platformColor(context, platform);
    final divider = AppColors.onScaffold(context).withValues(alpha: 0.07);
    return Pressable(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openCategory(context, category),
      child: Container(
        height: _chartRowHeight,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divider, width: 0.5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(
                ordinal.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                  color: AppColors.mutedText(context),
                  // 等宽数字，两列的编号才对得齐。
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  color: AppColors.onScaffold(context),
                ),
              ),
            ),
            if (ref.watch(
              currentMusicProvider.select((music) {
                if (music == null) return false;
                return ref.read(playerServiceProvider).nowPlayingLeaderboardId ==
                    category.id;
              }),
            ))
              Icon(Icons.graphic_eq_rounded, size: 13, color: color),
            // 最长的榜名（香港电台中文歌曲龙虎榜）会顶到列边界，留一点气口。
            const SizedBox(width: 6),
          ],
        ),
      ),
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

/// 横屏右栏的一行歌曲。
///
/// 单独做成 ConsumerWidget，而不是在 ListView 的 itemBuilder 里 watch：
/// 列表子项是在布局阶段建造的，在那里注册依赖会被 Riverpod 判成
/// 「build 之外改状态」。
class _ChartPaneSongRow extends ConsumerWidget {
  const _ChartPaneSongRow({
    required this.songs,
    required this.index,
    required this.categoryId,
  });

  final List<MusicItem> songs;
  final int index;
  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = songs[index];
    final isPlaying = ref.watch(
      currentMusicProvider.select(
        (current) => current?.identityKey == song.identityKey,
      ),
    );
    final divider = AppColors.onScaffold(context).withValues(alpha: 0.06);
    return Pressable(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        ref
            .read(playerServiceProvider)
            .setQueue(
              songs,
              startIndex: index,
              manualPlayName: song.name,
              leaderboardId: categoryId,
            );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divider, width: 0.5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: isPlaying
                  ? Icon(
                      Icons.graphic_eq_rounded,
                      size: 15,
                      color: AppColors.accentOf(context),
                    )
                  : Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: index < 3
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: index < 3
                            ? AppColors.accentOf(context)
                            : AppColors.mutedText(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 32,
                height: 32,
                child: song.artwork != null && song.artwork!.isNotEmpty
                    ? ArtworkImage(
                        song.artwork!,
                        cacheWidth: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.music_note,
                          size: 15,
                          color: AppColors.mutedText(context),
                        ),
                      )
                    : Icon(
                        Icons.music_note,
                        size: 15,
                        color: AppColors.mutedText(context),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: isPlaying
                          ? AppColors.accentOf(context)
                          : AppColors.onScaffold(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.singer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
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

/// 吸顶平台标题。上半段是实底（盖住滚上来的封面），下半段渐隐，
/// 让卡片看起来是从标题底下滑过去的。
class _PlatformHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PlatformHeaderDelegate({
    required this.extent,
    required this.contentExtent,
    required this.background,
    required this.child,
  });

  final double extent;
  final double contentExtent;
  final Color background;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: contentExtent,
          child: ColoredBox(color: background),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: contentExtent,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [background, background.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 0,
          height: contentExtent,
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _PlatformHeaderDelegate oldDelegate) {
    return oldDelegate.extent != extent ||
        oldDelegate.contentExtent != contentExtent ||
        oldDelegate.background != background ||
        oldDelegate.child != child;
  }
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

class _LeaderboardPlayButton extends ConsumerWidget {
  const _LeaderboardPlayButton({
    required this.category,
    required this.onPressed,
    this.diameter = 40,
  });

  final LeaderboardCategory category;
  final VoidCallback onPressed;

  /// 主卡上放大到 52，让「播这个榜」成为那一屏最明确的操作。
  final double diameter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNowPlaying = ref.watch(
      currentMusicProvider.select((music) {
        final service = ref.read(playerServiceProvider);
        return music != null && service.nowPlayingLeaderboardId == category.id;
      }),
    );
    // 浅色主题浅底深图标，深色主题深底浅图标。底色要透，封面颜色才出得来。
    final isDark = AppColors.isDark(context);
    final accent = AppColors.accentOf(context);
    final background = isNowPlaying
        ? accent
        : (isDark ? AppColors.bg : Colors.white);
    final iconColor = isNowPlaying
        ? Colors.white
        : (isDark ? AppColors.textPrimary : AppColors.lightText);
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: SizedBox.square(
        dimension: diameter,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: ColoredBox(
                  color: background.withValues(
                    alpha: isNowPlaying ? 0.88 : 0.34,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            CardPlayButton(
              size: diameter,
              tooltip: isNowPlaying
                  ? S.of(context).nowPlayingNamed(category.name)
                  : S.of(context).playNamed(category.name),
              color: iconColor,
              backgroundColor: Colors.transparent,
              onPressed: onPressed,
              icon: isNowPlaying
                  ? _NowPlayingSpin(
                      child: Icon(
                        Icons.music_note,
                        color: Colors.white,
                        size: diameter * 0.65,
                      ),
                    )
                  : Icon(
                      Icons.play_arrow_rounded,
                      color: iconColor,
                      size: diameter * 0.72,
                    ),
            ),
          ],
        ),
      ),
    );
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
