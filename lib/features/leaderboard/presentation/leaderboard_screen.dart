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
/// 三个平台都有且只有这一个恰好的名字（酷我另有一个「抖音热歌榜」，所以
/// 只能精确比对，不能用 contains）。它也是这一页唯一会被反复回访的榜，
/// 其余的榜大多是一次性浏览，压成小卡就够。
const String kHeroChartName = '热歌榜';

/// 榜单页：固定 QQ、酷我、网易云平台顺序，支持隐藏平台/榜单。
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  bool _layoutScheduled = false;

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
  static const double _heroRowHeight = 68;
  static const double _chartRowHeight = 34;

  /// 窄屏两列、宽屏三列。辅卡只剩榜名，210 以上放长榜名才不用省略号。
  static int _columnsFor(double contentWidth) => contentWidth >= 520 ? 3 : 2;

  Widget _buildLeaderboardList(
    BuildContext context,
    List<LeaderboardLayoutItem> visible,
    Map<String, LeaderboardCategory> categoryByKey,
    double contentWidth,
    bool isLandscapeShell,
  ) {
    final columns = _columnsFor(contentWidth);
    final sections = _groupByPlatform(visible, categoryByKey);
    final background = Theme.of(context).scaffoldBackgroundColor;
    // 视口从磨砂顶栏下面开始：吸顶的平台标题才不会被顶栏盖住。代价是
    // 内容不再从顶栏底下钻过去，但这一页有吸顶条，留白换结构更划算。
    // 横屏没有顶栏，但要躲开状态栏，否则吸顶条会压在电量图标上。
    final topInset = isLandscapeShell
        ? 12 + MediaQuery.paddingOf(context).top
        : FrostedTabHeader.extent(context);
    return Padding(
      padding: EdgeInsets.only(top: topInset),
      child: CustomScrollView(
        cacheExtent: 520,
        slivers: [
          for (final section in sections)
            // 每个平台是一个 sliver 组：组的结束会把组头的吸顶状态一起推走，
            // 否则每个段的标题都会一直叠在顶上（一次能看到三四条）。
            SliverMainAxisGroup(
              slivers: [
                if (section.platform != null)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PlatformHeaderDelegate(
                      extent: _headerExtent,
                      contentExtent: _headerContentExtent,
                      background: background,
                      child: _buildPlatformHeader(context, section),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: SizedBox(height: isLandscapeShell ? 12 : 8),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  // 整段一次建完：辅卡只剩编号和榜名，40 个榜也就是几十行文本，
                  // 懒加载省下来的那点开销还不够两层 sliver 的复杂度。
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (section.hero != null) ...[
                          _buildHeroRow(context, section.hero!),
                          const SizedBox(height: 10),
                        ],
                        ..._buildChartRows(context, section.cards, columns),
                      ],
                    ),
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
    );
  }

  /// 辅卡排成等宽列。编号按阅读顺序从左到右数，不是榜单名次——名次是
  /// 详情页里那 100 首歌的事，这里只是「第几个」。
  List<Widget> _buildChartRows(
    BuildContext context,
    List<LeaderboardCategory> cards,
    int columns,
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
                ? _buildChartCell(context, cards[index], index + 1)
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
        // 段里精确叫「热歌榜」的那个当主卡，其余保持用户排好的顺序。
        // 用户把它隐藏了、或者平台以后改了名，hero 就是 null，这一段退回
        // 纯列表——不要拿别的榜顶替，否则「最大的那张」含义就不成立了。
        LeaderboardCategory? hero;
        for (final card in cards) {
          if (card.name == kHeroChartName) {
            hero = card;
            break;
          }
        }
        final rest = hero == null
            ? cards
            : cards.where((card) => card.id != hero!.id).toList(growable: false);
        sections.add(
          _LeaderboardSection(header: header, hero: hero, cards: rest),
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

  /// 段首主行：热歌榜。它拿走了这一页唯一的一块平台色，所以其余榜
  /// 退成纯文字——封面在三个平台之间没有统一风格，只有这一行需要露脸。
  Widget _buildHeroRow(BuildContext context, LeaderboardCategory category) {
    final platform = category.platform ?? 'other';
    final color = _platformColor(context, platform);
    final isDark = AppColors.isDark(context);
    // 首歌数来自已有的 provider：加载完就有，没加载完就不显示，
    // 不拿「每日更新」这种编出来的文案占位。
    final songs = ref
        .watch(leaderboardSongsProvider(category.id))
        .valueOrNull;
    final songCount = songs?.length;
    // 分类接口不再逐榜拉封面，主行封面直接取榜单首曲的封面。
    final cover = category.coverUrl ??
        (songs != null && songs.isNotEmpty ? songs.first.artwork : null);
    return Pressable(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openCategory(context, category),
      child: Container(
        height: _heroRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.20 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.36 : 0.18),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.square(
                dimension: 52,
                child: cover != null && cover.isNotEmpty
                    ? ArtworkImage(
                        cover,
                        cacheWidth: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _LeaderboardPlaceholder(
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
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                      height: 1.2,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  if (songCount != null && songCount > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      // 平台名上面段头已经写了，这里只补歌数。
                      S.of(context).songCount(songCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.mutedText(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _LeaderboardPlayButton(
              category: category,
              diameter: 34,
              onPressed: () => _playLeaderboard(ref, category),
            ),
          ],
        ),
      ),
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

/// 一个平台段：平台标题（可能为 null）+ 该平台的主卡 + 其余榜单的辅卡。
class _LeaderboardSection {
  const _LeaderboardSection({
    required this.header,
    required this.cards,
    this.hero,
  });

  final LeaderboardLayoutItem? header;

  /// 段首主卡（热歌榜）。为 null 时这一段只有辅卡。
  final LeaderboardCategory? hero;

  /// 辅卡，已排除 [hero]。
  final List<LeaderboardCategory> cards;

  /// 这一段实际展示的榜单总数，含主卡。
  int get chartCount => cards.length + (hero == null ? 0 : 1);

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
          left: 12,
          right: 12,
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
