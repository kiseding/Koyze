import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/search_sheet.dart';
import '../../../core/widgets/sleep_timer_sheet.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../player/presentation/player_provider.dart';
import '../../settings/presentation/settings_provider.dart';

/// 首页：搜索入口 + 快捷功能 + 随机播放收藏。
/// 竖屏单列、大屏居中并自适应列数，底部导航由 MainScaffold 提供。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// 定位首页标题文字，供搜索弹窗计算顶部高度。
  final GlobalKey _brandKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    final favorites = playlists
        .where((playlist) => playlist.id == 'favorites')
        .firstOrNull;
    final favoriteCount = favorites?.songCount ?? 0;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 底部安全区已由 MainScaffold（底栏+迷你栏）处理，避免双重留白
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isWide = width >= 720;
              // 大屏内容居中，保持阅读宽度。
              final contentWidth = isWide ? min(width * 0.82, 900.0) : width;
              final columns = isWide ? 4 : 2;

              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 0 : 16,
                    vertical: 12,
                  ),
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 14),
                        _buildSearchBar(context),
                        const SizedBox(height: 20),
                        _buildRandomFavoriteCard(context, ref, favoriteCount),
                        const SizedBox(height: 24),
                        _buildQuickSectionTitle(context, '快捷功能'),
                        const SizedBox(height: 12),
                        _buildQuickGrid(context, ref, columns),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openSearchSheet(BuildContext context) {
    // 弹窗顶部对齐首页 Koyze 文字顶部上方 3px。
    double topInset = 0;
    final box = _brandKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.attached) {
      topInset = box.localToGlobal(Offset.zero).dy - 3;
    }
    showSearchSheet(context, topInset: topInset > 0 ? topInset : 0);
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Koyze',
                key: _brandKey,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentOf(context),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Enjoy Music',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.mutedText(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 搜索条占一行：点击弹出搜索弹窗（滑入动画，2/3 时弹输入法）。
  Widget _buildSearchBar(BuildContext context) {
    final muted = AppColors.mutedText(context);
    final border = AppColors.cardBorder(context);
    return Pressable(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openSearchSheet(context),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.miniBar(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: muted, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '搜索歌曲、歌手、歌单...',
                style: TextStyle(color: muted, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一键随机播放收藏列表。
  Widget _buildRandomFavoriteCard(
    BuildContext context,
    WidgetRef ref,
    int favoriteCount,
  ) {
    final accent = AppColors.accentOf(context);
    const onAccent = Colors.white;

    return HoverFloat(
      child: Pressable(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.pushNamed(
          'playlistDetail',
          pathParameters: {'playlistId': 'favorites'},
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withAlpha(230), accent.withAlpha(120)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: accent.withAlpha(50),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: onAccent.withAlpha(36),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.favorite, color: onAccent, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '收藏列表',
                      style: TextStyle(
                        color: onAccent,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      favoriteCount == 0
                          ? '还没有收藏歌曲'
                          : '共 $favoriteCount 首 · 点击查看，右侧随机播放',
                      style: TextStyle(
                        color: onAccent.withAlpha(210),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Pressable(
                scale: 0.9,
                semanticLabel: '随机播放收藏',
                onTap: favoriteCount == 0
                    ? null
                    : () => _playRandomFavorites(ref),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: onAccent.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shuffle, color: onAccent, size: 26),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _playRandomFavorites(WidgetRef ref) async {
    try {
      final playlistService = ref.read(playlistServiceProvider);
      final favorites = playlistService.favorites;
      if (favorites == null || favorites.songCount <= 0) {
        showAppNotification('还没有收藏歌曲', type: AppNotificationType.info);
        return;
      }
      final songCount = favorites.songCount;
      final playerService = ref.read(playerServiceProvider);
      // 惰性分页随机播放：不要求全量加载，大收藏列表也稳定。
      await playerService.setShuffleMode(true);
      await playerService.playPagedPlaylist(
        songCount: songCount,
        startIndex: Random().nextInt(songCount),
        playlistId: 'favorites',
        manual: true,
        loadPage: (offset, limit) async {
          final page = await playlistService.getSongsPage(
            'favorites',
            offset: offset,
            limit: limit,
          );
          return page.songs;
        },
      );
    } catch (error) {
      if (!mounted) return;
      showAppNotification('随机播放失败: $error', type: AppNotificationType.error);
    }
  }

  Widget _buildQuickSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.onScaffold(context),
      ),
    );
  }

  Widget _buildQuickGrid(BuildContext context, WidgetRef ref, int columns) {
    final entries = <_QuickEntry>[
      const _QuickEntry(
        title: '猜你喜欢',
        subtitle: '根据历史推荐',
        icon: Icons.auto_awesome,
        route: '/recommend',
        color: Color(0xFFFF8F1F),
      ),
      const _QuickEntry(
        title: '本地音乐',
        subtitle: '设备上的歌曲',
        icon: Icons.library_music,
        route: 'localPlaylist',
        color: Colors.purple,
      ),
      const _QuickEntry(
        title: '下载管理',
        subtitle: '任务与进度',
        icon: Icons.download_rounded,
        route: '/download',
        color: Color(0xFF0A84FF),
      ),
      const _QuickEntry(
        title: '听歌统计',
        subtitle: '周月年排行',
        icon: Icons.bar_chart_rounded,
        route: '/stats',
        color: Color(0xFF28A745),
      ),
      const _QuickEntry(
        title: '睡眠定时',
        subtitle: '定时停止播放',
        icon: Icons.bedtime_outlined,
        route: '',
        color: Color(0xFF5B7DB1),
        action: _QuickAction.sleepTimer,
      ),
      const _QuickEntry(
        title: '切换主题',
        subtitle: '深色 / 浅色',
        icon: Icons.palette_outlined,
        route: '',
        color: Color(0xFF9E9E9E),
        action: _QuickAction.themeToggle,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final entry in entries)
              SizedBox(
                width: tileWidth,
                child: _QuickEntryCard(entry: entry),
              ),
          ],
        );
      },
    );
  }
}

/// 快捷功能特殊交互。
enum _QuickAction { sleepTimer, themeToggle }

class _QuickEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final Color color;
  final _QuickAction? action;

  const _QuickEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.color,
    this.action,
  });
}

class _QuickEntryCard extends ConsumerWidget {
  final _QuickEntry entry;

  const _QuickEntryCard({required this.entry});

  void _toggleTheme(WidgetRef ref) {
    final current = ref.read(themeModeProvider);
    final next = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    ref.read(themeModeProvider.notifier).setThemeMode(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = entry.color;
    return Pressable(
      borderRadius: BorderRadius.circular(14),
      captureExpandRect: entry.action == null,
      onTap: () {
        switch (entry.action) {
          case _QuickAction.sleepTimer:
            showSleepTimerSheet(context, ref);
          case _QuickAction.themeToggle:
            _toggleTheme(ref);
          case null:
            if (entry.route == 'localPlaylist') {
              context.pushNamed(
                'playlistDetail',
                pathParameters: {'playlistId': 'local'},
              );
            } else {
              context.push(entry.route);
            }
        }
      },
      child: _buildCardBody(context, ref, color),
    );
  }

  Widget _buildCardBody(BuildContext context, WidgetRef ref, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(entry.icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onScaffold(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.subtitle,
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
          Icon(
            Icons.chevron_right,
            color: AppColors.mutedText(context),
            size: 18,
          ),
        ],
      ),
    );
  }
}
