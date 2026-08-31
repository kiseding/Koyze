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
import 'home_quick_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../core/widgets/fx_switch.dart';

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
    final quickSettings = ref.watch(homeQuickSettingsProvider);
    final quickIds = [
      for (final id in quickSettings.order)
        if (quickSettings.enabled.contains(id)) id,
    ];
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
                        _buildQuickGrid(context, ref, columns, quickIds),
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
        Pressable(
          semanticLabel: '设置快捷功能',
          onTap: () => _showQuickSettings(context),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.miniBar(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.tune,
              color: AppColors.secondaryText(context),
              size: 20,
            ),
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
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: AppColors.isDark(context) ? 0.25 : 0.04,
              ),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
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
        borderRadius: BorderRadius.circular(20),
        captureExpandRect: true,
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
              colors: [
                accent,
                Color.lerp(accent, const Color(0xFF007AFF), 0.28)!,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: onAccent.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: onAccent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          '收藏列表',
                          style: TextStyle(
                            color: onAccent,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (favoriteCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: onAccent.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$favoriteCount',
                              style: const TextStyle(
                                color: onAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      favoriteCount == 0 ? '还没有收藏歌曲' : '点击查看，右侧随机播放',
                      style: TextStyle(
                        color: onAccent.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
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
                    color: onAccent.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: const Icon(
                    Icons.shuffle_rounded,
                    color: onAccent,
                    size: 24,
                  ),
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

  Widget _buildQuickGrid(
    BuildContext context,
    WidgetRef ref,
    int columns,
    List<String> quickIds,
  ) {
    final entries = [
      for (final id in quickIds)
        homeQuickFeatures.firstWhere((entry) => entry.id == id),
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

  void _showQuickSettings(BuildContext context) {
    showKoyzeSheet(
      context: context,
      backgroundColor: AppColors.dialogBg(context),
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(homeQuickSettingsProvider);
          final enabled = settings.enabled;
          final notifier = ref.read(homeQuickSettingsProvider.notifier);
          final order = settings.order;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 2 / 3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '快捷功能设置',
                          style: TextStyle(
                            color: AppColors.onScaffold(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FxIconButton(
                        tooltip: '关闭快捷功能设置',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: order.length,
                    onReorderItem: notifier.reorder,
                    itemBuilder: (context, index) {
                      final feature = homeQuickFeatures.firstWhere(
                        (item) => item.id == order[index],
                      );
                      final active = enabled.contains(feature.id);
                      return ListTile(
                        key: ValueKey(feature.id),
                        leading: Icon(feature.icon, color: feature.color),
                        title: Text(
                          feature.title,
                          style: TextStyle(
                            color: active
                                ? AppColors.onScaffold(context)
                                : AppColors.mutedText(context),
                          ),
                        ),
                        subtitle: Text(
                          feature.subtitle,
                          style: TextStyle(
                            color: AppColors.mutedText(context),
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FxSwitch(
                              value: active,
                              onChanged: (value) =>
                                  notifier.setEnabled(feature.id, value),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: AppColors.mutedText(context),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 快捷功能特殊交互。
class _QuickEntryCard extends ConsumerWidget {
  final HomeQuickFeature entry;

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
          case HomeQuickAction.sleepTimer:
            showSleepTimerSheet(context, ref);
          case HomeQuickAction.themeToggle:
            _toggleTheme(ref);
          case null:
            if (entry.route == 'localPlaylist' ||
                entry.route == 'favoritesPlaylist' ||
                entry.route == 'recentPlaylist') {
              context.pushNamed(
                'playlistDetail',
                pathParameters: {
                  'playlistId': switch (entry.route) {
                    'localPlaylist' => 'local',
                    'favoritesPlaylist' => 'favorites',
                    _ => 'recent',
                  },
                },
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
    final isDark = AppColors.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.cardBorder(context), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: isDark ? 0.28 : 0.18),
                  color.withValues(alpha: isDark ? 0.12 : 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: isDark ? 0.35 : 0.22),
                width: 0.6,
              ),
            ),
            child: Icon(entry.icon, color: color, size: 21),
          ),
          const SizedBox(width: 11),
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
                    letterSpacing: -0.2,
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
            Icons.chevron_right_rounded,
            color: AppColors.mutedText(context).withValues(alpha: 0.6),
            size: 18,
          ),
        ],
      ),
    );
  }
}
