import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/music_source/platform/music_platform.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/card_play_button.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/frosted_tab_header.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../core/widgets/pressable.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import 'leaderboard_provider.dart';

const Map<String, String> kLeaderboardPlatformNames = {
  'tx': 'QQ音乐',
  'kw': '酷我音乐',
  'wy': '网易云',
};

/// 榜单页：固定 QQ、酷我、网易云平台顺序，支持隐藏平台/榜单。
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
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

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 底部安全区已由 MainScaffold（底栏+迷你栏）处理。
        // 顶部不包 SafeArea：磨砂要铺到屏幕顶（含灵动岛/状态栏）。
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= 720;
            final contentWidth = isWide ? min(width * 0.82, 900.0) : width;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: categoriesAsync.when(
                        loading: () => const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.amber,
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
                                '加载失败: $error',
                                style: TextStyle(
                                  color: AppColors.secondaryText(context),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => ref.invalidate(
                                  leaderboardCategoriesProvider,
                                ),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                        data: (categories) {
                          if (categories.isEmpty) {
                            return Center(
                              child: Text(
                                '暂无排行榜数据',
                                style: TextStyle(
                                  color: AppColors.mutedText(context),
                                ),
                              ),
                            );
                          }
                          // 首次加载生成默认布局。
                          ref
                              .read(leaderboardLayoutProvider.notifier)
                              .ensureDefaultLayout(categories);
                          final layout = ref.watch(leaderboardLayoutProvider);
                          final visible = <LeaderboardLayoutItem>[];
                          for (final item in layout) {
                            if (!item.hidden) visible.add(item);
                          }

                          if (visible.isEmpty) {
                            return Center(
                              child: Text(
                                '已隐藏全部榜单\n点击右上角设置恢复',
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
                          );
                        },
                      ),
                    ),
                    // 标题栏悬浮铺到屏幕顶（含状态栏/灵动岛），整栏磨砂玻璃；
                    // 列表可滚动到栏内部，磨砂才可见。
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: FrostedTabHeader(
                        title: '榜单',
                        subtitle: '发现各平台正在热播的音乐',
                        leadingIcon: Icons.leaderboard_rounded,
                        actions: [
                          FrostedHeaderButton(
                            icon: Icons.tune_rounded,
                            semanticLabel: '榜单设置',
                            onTap: () => context.push('/leaderboard-settings'),
                          ),
                          FrostedHeaderButton(
                            icon: Icons.refresh_rounded,
                            semanticLabel: '刷新榜单',
                            onTap: () => ref.invalidate(
                              leaderboardCategoriesProvider,
                            ),
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

  static const double _cardGap = 10;
  static const double _cardMaxSize = 200;
  static const int _minColumns = 2;

  static int _columnsFor(double contentWidth) {
    final available = max(0.0, contentWidth - 24);
    var columns = _minColumns;
    while (columns < 8) {
      final size = (available - _cardGap * (columns - 1)) / columns;
      if (size <= _cardMaxSize) return columns;
      columns += 1;
    }
    return columns;
  }

  Widget _buildLeaderboardList(
    BuildContext context,
    List<LeaderboardLayoutItem> visible,
    Map<String, LeaderboardCategory> categoryByKey,
    double contentWidth,
  ) {
    final columns = _columnsFor(contentWidth);
    final rows = _packLeaderboardRows(visible, columns);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        12,
        FrostedTabHeader.extent(context),
        12,
        16,
      ),
      cacheExtent: 520,
      itemCount: rows.length,
      itemBuilder: (context, index) =>
          _buildPackedItem(context, rows[index], categoryByKey, columns),
    );
  }

  List<_LeaderboardPackedItem> _packLeaderboardRows(
    List<LeaderboardLayoutItem> visible,
    int columns,
  ) {
    final rows = <_LeaderboardPackedItem>[];
    final pending = <LeaderboardLayoutItem>[];

    void flushCards() {
      for (var i = 0; i < pending.length; i += columns) {
        final end = min(i + columns, pending.length);
        rows.add(_LeaderboardPackedItem.cards(pending.sublist(i, end)));
      }
      pending.clear();
    }

    for (var i = 0; i < visible.length; i++) {
      final item = visible[i];
      if (item.isPlatform) {
        flushCards();
        final isLastOfBlock =
            i == visible.length - 1 || visible[i + 1].isPlatform;
        rows.add(_LeaderboardPackedItem.header(item, isLastOfBlock));
      } else {
        pending.add(item);
      }
    }
    flushCards();
    return rows;
  }

  Widget _buildPackedItem(
    BuildContext context,
    _LeaderboardPackedItem row,
    Map<String, LeaderboardCategory> categoryByKey,
    int columns,
  ) {
    if (row.header != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: _buildPlatformHeader(context, row.header!, row.isLastOfBlock),
      );
    }
    final cards = row.cards;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          for (var i = 0; i < columns; i++) ...[
            if (i > 0) const SizedBox(width: _cardGap),
            Expanded(
              child: i < cards.length
                  ? _buildLeaderboardCard(context, categoryByKey[cards[i].key])
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlatformHeader(
    BuildContext context,
    LeaderboardLayoutItem item,
    bool isLastOfBlock,
  ) {
    final platform = item.platformId ?? 'other';
    final name = kLeaderboardPlatformNames[platform] ?? '其他';
    final color = _platformColor(context, platform);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_platformIcon(platform), color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onScaffold(context),
            ),
          ),
          const Spacer(),
          Text(
            isLastOfBlock ? '榜单' : '精选',
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }

  IconData _platformIcon(String platform) {
    switch (platform) {
      case 'tx':
        return Icons.music_note_rounded;
      case 'kw':
        return Icons.graphic_eq_rounded;
      case 'wy':
        return Icons.album_rounded;
      default:
        return Icons.library_music_rounded;
    }
  }

  Widget _buildLeaderboardCard(
    BuildContext context,
    LeaderboardCategory? category,
  ) {
    if (category == null) return const SizedBox.shrink();
    final cover = category.coverUrl;
    final platform = category.platform ?? 'other';
    const radius = 18.0;
    return AspectRatio(
      aspectRatio: 1,
      child: Pressable(
        borderRadius: BorderRadius.circular(radius),
        captureExpandRect: true,
        onTap: () {
          context.push(
            '/leaderboard/detail?id=${Uri.encodeComponent(category.id)}'
            '&name=${Uri.encodeComponent(category.name)}',
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              cover != null && cover.isNotEmpty
                  ? ArtworkImage(
                      cover,
                      cacheWidth: 400,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _LeaderboardPlaceholder(
                        platform: platform,
                        name: category.name,
                      ),
                    )
                  : _LeaderboardPlaceholder(
                      platform: platform,
                      name: category.name,
                    ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x99000000),
                      Color(0x14000000),
                      Color(0xB3000000),
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                right: 68,
                child: Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.2,
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 8)],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: _LeaderboardPlayButton(
                  category: category,
                  color: Colors.white,
                  onPressed: () => _playLeaderboard(ref, category),
                ),
              ),
            ],
          ),
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

class _LeaderboardPackedItem {
  const _LeaderboardPackedItem.header(this.header, this.isLastOfBlock)
    : cards = const [];

  const _LeaderboardPackedItem.cards(this.cards)
    : header = null,
      isLastOfBlock = false;

  final LeaderboardLayoutItem? header;
  final bool isLastOfBlock;
  final List<LeaderboardLayoutItem> cards;
}

/// 封面加载失败或无封面时的渐变占位。
class _LeaderboardPlaceholder extends StatelessWidget {
  final String platform;
  final String name;

  const _LeaderboardPlaceholder({required this.platform, required this.name});

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
          size: 48,
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
    required this.color,
    required this.onPressed,
  });

  final LeaderboardCategory category;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNowPlaying = ref.watch(
      currentMusicProvider.select((music) {
        final service = ref.read(playerServiceProvider);
        return music != null && service.nowPlayingLeaderboardId == category.id;
      }),
    );
    return CardPlayButton(
      size: 60,
      tooltip: isNowPlaying ? '正在播放 ${category.name}' : '播放 ${category.name}',
      color: color,
      backgroundColor: isNowPlaying
          ? Colors.white.withValues(alpha: 0.32)
          : Colors.black.withValues(alpha: 0.38),
      onPressed: onPressed,
      icon: isNowPlaying
          ? _NowPlayingSpin(
              child: Icon(Icons.music_note, color: color, size: 36),
            )
          : Icon(Icons.play_arrow_rounded, color: color, size: 40),
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
            child: CircularProgressIndicator(
              color: AppColors.accentOf(context),
            ),
          ),
          error: (e, _) => Center(
            child: Text(
              '加载失败: $e',
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
          data: (songs) {
            if (songs.isEmpty) {
              return Center(
                child: Text(
                  '暂无歌曲数据',
                  style: TextStyle(color: AppColors.mutedText(context)),
                ),
              );
            }
            return ListView.builder(
              cacheExtent: 420,
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
    final favoriteIds =
        ref.watch(favoriteIdsProvider).valueOrNull ?? const <String>{};
    final isPlaying = ref.watch(
      currentMusicProvider.select(
        (current) => current?.identityKey == song.identityKey,
      ),
    );
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  isFavorite: favoriteIds.contains(song.identityKey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
