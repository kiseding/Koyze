import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../player/presentation/player_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../playlist/presentation/playlist_picker.dart';
import '../../download/presentation/download_provider.dart';
import 'search_provider.dart';
import 'song_list_detail_screen.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/favorite_button.dart';
import 'package:animations/animations.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/motion/list_entrance.dart';
import '../../../core/widgets/koyze_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.autofocusDelay});

  /// 进入后延迟聚焦输入框并弹出输入法。
  /// 首页搜索弹窗在滑入 2/3 时聚焦；独立搜索页立即聚焦。
  final Duration? autofocusDelay;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _autofocusTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 进入页面后聚焦输入框并弹出输入法（配合展开动效）。
    // 首页弹窗按 autofocusDelay 延迟到滑入 2/3 时聚焦。
    final delay = widget.autofocusDelay;
    if (delay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _autofocusTimer = Timer(delay, () {
        if (mounted) _searchFocus.requestFocus();
      });
    }
    // 只在「是否有文字」变化时 setState（清除按钮显隐）。
    // 禁止在 selection/composing 变化时重建：首次聚焦会改 selection，
    // 整页 rebuild 会导致 iOS 输入法秒关。
    var hadText = _searchController.text.isNotEmpty;
    _searchController.addListener(() {
      final nowHas = _searchController.text.isNotEmpty;
      if (nowHas != hadText && mounted) {
        hadText = nowHas;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _autofocusTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadMore();
    }
  }

  void _loadMore() {
    ref.read(searchStateProvider.notifier).loadMore();
  }

  void _onSearch(String query) {
    if (query.trim().isNotEmpty) {
      ref.read(searchQueryProvider.notifier).state = query.trim();
      ref.read(searchStateProvider.notifier).search(query.trim());
      ref.read(searchHistoryProvider.notifier).add(query.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchStateProvider);
    final selectedSourceId = ref.watch(selectedSourceIdProvider);
    final allSources = ref.watch(allSearchSourcesProvider);
    final searchHistory = ref.watch(searchHistoryProvider);
    final accent = AppColors.accentOf(context);
    final primary = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    final border = AppColors.cardBorder(context);

    final list = allSources;
    final current = list.cast<SearchSourceItem?>().firstWhere(
      (s) => s?.id == selectedSourceId,
      orElse: () => list.isNotEmpty ? list.first : null,
    );

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 禁止随键盘改 body 高度，避免首焦布局抖动导致输入法秒关。
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            children: [
              // 平台、输入与触发操作独立成组，避免一整条控件显得拥挤。
              // 进入时展开动效：平台选择与搜索按钮自两侧滑入，输入框轻微上移。
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: motionDuration(
                    context,
                    const Duration(milliseconds: 400),
                  ),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Row(
                    children: [
                      // 平台选择：自左侧滑入
                      Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(-40 * (1 - t), 0),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.miniBar(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: border.withValues(alpha: 0.6),
                              ),
                            ),
                            child: PopupMenuButton<String>(
                              tooltip: '选择平台',
                              offset: const Offset(0, 8),
                              color: AppColors.dialogBg(context),
                              elevation: 10,
                              shadowColor: Colors.black.withValues(alpha: 0.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              popUpAnimationStyle: AnimationStyle(
                                duration: motionDuration(
                                  context,
                                  MotionDuration.normal,
                                ),
                                reverseDuration: motionDuration(
                                  context,
                                  MotionDuration.micro,
                                ),
                                curve: MotionCurve.easeOut,
                                reverseCurve: MotionCurve.easeIn,
                              ),
                              onSelected: (id) {
                                ref
                                        .read(selectedSourceIdProvider.notifier)
                                        .state =
                                    id;
                                if (_searchController.text.isNotEmpty) {
                                  _onSearch(_searchController.text);
                                }
                              },
                              itemBuilder: (ctx) => [
                                for (final s in list)
                                  PopupMenuItem(
                                    value: s.id,
                                    height: 44,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            s.name,
                                            style: TextStyle(
                                              color: primary,
                                              fontWeight:
                                                  s.id == selectedSourceId
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        if (s.id == selectedSourceId)
                                          Icon(
                                            Icons.check_rounded,
                                            color: accent,
                                            size: 18,
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      current?.name ?? '平台',
                                      style: TextStyle(
                                        color: primary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: muted,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 输入框：进入时轻微上移（Transform 需在 Expanded 内层）
                      Expanded(
                        child: Transform.translate(
                          offset: Offset(0, -6 * (1 - t)),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.miniBar(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: border.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocus,
                                    autofocus: true,
                                    style: TextStyle(
                                      color: primary,
                                      fontSize: 15,
                                      height: 1.2,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '搜索歌曲、歌单...',
                                      hintStyle: TextStyle(
                                        color: muted,
                                        fontSize: 15,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      filled: false,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 12,
                                          ),
                                    ),
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: _onSearch,
                                  ),
                                ),
                                if (_searchController.text.isNotEmpty)
                                  FxIconButton(
                                    tooltip: '清除搜索内容',
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.clear,
                                      size: 18,
                                      color: muted,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      ref
                                              .read(
                                                searchQueryProvider.notifier,
                                              )
                                              .state =
                                          '';
                                      ref
                                          .read(searchStateProvider.notifier)
                                          .reset();
                                      setState(() {});
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 搜索按钮：自右侧滑入
                      Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(40 * (1 - t), 0),
                          child: SizedBox(
                            height: 44,
                            child: FilledButton(
                              onPressed: () =>
                                  _onSearch(_searchController.text),
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                '搜索',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: _buildMainContent(searchState, searchHistory)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(
    SearchState searchState,
    List<String> searchHistory,
  ) {
    // 状态切换（历史/加载/结果/错误）走 Fade Through：旧内容淡出、新内容淡入。
    return PageTransitionSwitcher(
      duration: motionDuration(context, MotionDuration.normal),
      reverse: true,
      transitionBuilder: (child, primaryAnimation, secondaryAnimation) {
        final curved = CurvedAnimation(
          parent: primaryAnimation,
          curve: MotionCurve.easeOut,
          reverseCurve: MotionCurve.easeIn,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: MotionScale.contentIn,
              end: 1,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: _buildContentByState(searchState, searchHistory),
    );
  }

  Widget _buildContentByState(
    SearchState searchState,
    List<String> searchHistory,
  ) {
    if (searchState.items.isEmpty &&
        _searchController.text.isEmpty &&
        !searchState.isLoading) {
      return _buildHistory(searchHistory);
    }
    if (searchState.isLoading && searchState.items.isEmpty) {
      return Center(
        key: const ValueKey('search-loading'),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              AppColors.accentOf(context),
            ),
          ),
        ),
      );
    }
    if (searchState.error != null && searchState.items.isEmpty) {
      return Center(
        key: const ValueKey('search-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '搜索出错: ${searchState.error}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => ref
                  .read(searchStateProvider.notifier)
                  .search(searchState.query),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return _buildResultList(searchState);
  }

  Widget _buildResultList(SearchState searchState) {
    final results = searchState.items;
    final localMatches = searchState.localMatches;
    // 页面级一次性读取收藏集合，避免每个可见行创建异步收藏查询。
    final favoriteIds =
        ref.watch(favoriteIdsProvider).valueOrNull ?? const <String>{};
    if (results.isEmpty && localMatches.isEmpty && !searchState.isLoading) {
      return Center(
        key: const ValueKey('search-empty'),
        child: Text(
          '无结果',
          style: TextStyle(color: AppColors.mutedText(context)),
        ),
      );
    }
    final localSectionCount =
        localMatches.length + (localMatches.isNotEmpty ? 1 : 0);
    final networkSectionCount =
        results.isNotEmpty &&
            searchState.sourceId != 'local' &&
            searchState.sourceId != 'favorites'
        ? 1
        : 0;
    final leadingCount = localSectionCount + networkSectionCount;
    return ListView.builder(
      key: ValueKey('results-${searchState.generation}'),
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: results.length + (searchState.hasMore ? 1 : 0) + leadingCount,
      itemBuilder: (context, index) {
        if (index < leadingCount) {
          if (index == 0 && localMatches.isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.library_music,
                    size: 16,
                    color: AppColors.accentOf(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '本地音乐',
                    style: TextStyle(
                      color: AppColors.accentOf(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }
          if (index == localSectionCount && networkSectionCount == 1) {
            return Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Divider(color: AppColors.cardBorder(context)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '网络音乐',
                      style: TextStyle(
                        color: AppColors.mutedText(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(color: AppColors.cardBorder(context)),
                  ),
                ],
              ),
            );
          }
          final local = localMatches[index - (localMatches.isNotEmpty ? 1 : 0)];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () {
              final playable = localMatches.where((e) => e.isPlayable).toList();
              ref
                  .read(playerServiceProvider)
                  .setQueue(
                    playable,
                    startIndex: playable.indexWhere(
                      (e) => e.identityKey == local.identityKey,
                    ),
                    manualPlayName: local.name,
                  );
            },
            onLongPress: () => _showSongMenu(local, localMatches),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: AppColors.miniBar(context),
                child: local.artwork != null && local.artwork!.isNotEmpty
                    ? ArtworkImage(
                        local.artwork!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : Icon(
                        Icons.audiotrack,
                        color: AppColors.accentOf(context),
                        size: 24,
                      ),
              ),
            ),
            title: Text(
              local.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.onScaffold(context)),
            ),
            subtitle: Text(
              '${local.singer} · 本地',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.mutedText(context),
                fontSize: 12,
              ),
            ),
          );
        }
        final resultIndex = index - leadingCount;
        if (resultIndex == results.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: searchState.isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.accentOf(context),
                        ),
                      ),
                    )
                  : Text(
                      '滑动加载更多',
                      style: TextStyle(
                        color: AppColors.mutedText(context),
                        fontSize: 12,
                      ),
                    ),
            ),
          );
        }
        final item = results[resultIndex];
        final isSonglist = !item.isPlayable;
        return ListEntrance(
          key: ValueKey('song-${item.id}'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () {
              if (isSonglist) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SongListDetailScreen(songList: item),
                  ),
                );
              } else {
                final playable = results.where((e) => e.isPlayable).toList();
                final pIndex = playable.indexWhere(
                  (e) => e.identityKey == item.identityKey,
                );
                ref
                    .read(playerServiceProvider)
                    .setQueue(
                      playable,
                      startIndex: pIndex >= 0 ? pIndex : 0,
                      manualPlayName: item.name,
                    );
              }
            },
            onLongPress: isSonglist
                ? null
                : () => _showSongMenu(
                    item,
                    results.where((e) => e.isPlayable).toList(),
                  ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: item.artwork != null && item.artwork!.isNotEmpty
                    ? ArtworkImage(
                        item.artwork!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.onScaffold(context),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              isSonglist
                  ? item.singer
                  : '${item.singer}${item.album.isNotEmpty ? ' · ${item.album}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.mutedText(context),
                fontSize: 12,
              ),
            ),
            trailing: isSonglist
                ? Icon(Icons.chevron_right, color: AppColors.mutedText(context))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FavoriteButton(
                        song: item,
                        isFavorite: favoriteIds.contains(item.identityKey),
                      ),
                      FxIconButton(
                        tooltip: '更多操作',
                        icon: Icon(
                          Icons.more_vert,
                          color: AppColors.mutedText(context),
                          size: 20,
                        ),
                        onPressed: () => _showSongMenu(
                          item,
                          results.where((e) => e.isPlayable).toList(),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.fill2(context),
    child: Icon(Icons.music_note, color: AppColors.mutedText(context)),
  );

  Widget _buildHistory(List<String> searchHistory) {
    final hotAsync = ref.watch(hotSearchProvider);
    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);
    final muted = AppColors.mutedText(context);
    final accent = AppColors.accentOf(context);

    return ListView(
      // 底部已由 MainScaffold 预留，勿再垫 100 造成空白层
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (searchHistory.isNotEmpty) ...[
          Row(
            children: [
              Text(
                '搜索历史',
                style: TextStyle(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(searchHistoryProvider.notifier).clear(),
                child: Text(
                  '清空',
                  style: TextStyle(color: accent, fontSize: 12),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: searchHistory.map((h) {
              return ActionChip(
                label: Text(h, style: TextStyle(color: primary, fontSize: 13)),
                backgroundColor: AppColors.fill(context),
                side: BorderSide(color: AppColors.cardBorder(context)),
                onPressed: () {
                  _searchController.text = h;
                  _onSearch(h);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
        Text(
          '热搜榜',
          style: TextStyle(
            color: secondary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        hotAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('加载中...', style: TextStyle(color: muted, fontSize: 13)),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (hots) => Column(
            children: [
              for (var i = 0; i < hots.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        // 数字跟随主题：前三强调色，其余主文字
                        color: i < 3
                            ? accent
                            : primary.withValues(alpha: i < 10 ? 0.78 : 0.55),
                        fontSize: 15,
                        fontWeight: i < 3 ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(
                    hots[i],
                    style: TextStyle(color: primary, fontSize: 14),
                  ),
                  onTap: () {
                    _searchController.text = hots[i];
                    _onSearch(hots[i]);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSongMenu(dynamic item, List playableItems) {
    showKoyzeSheet(
      context: context,
      backgroundColor: AppColors.dialogBg(context),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.play_arrow,
                color: AppColors.onScaffold(context),
              ),
              title: Text(
                '立即播放',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                final pIndex = playableItems.indexWhere(
                  (e) => e.identityKey == item.identityKey,
                );
                ref
                    .read(playerServiceProvider)
                    .setQueue(
                      playableItems.cast(),
                      startIndex: pIndex >= 0 ? pIndex : 0,
                      manualPlayName: item.name,
                    );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.playlist_add,
                color: AppColors.onScaffold(context),
              ),
              title: Text(
                '添加到歌单',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                showPlaylistPicker(context: context, ref: ref, song: item);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.favorite_border,
                color: AppColors.onScaffold(context),
              ),
              title: Text(
                '收藏',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(toggleFavoriteProvider)(item);
                } catch (error) {
                  if (!mounted) return;
                  showAppNotification(
                    '收藏失败: $error',
                    type: AppNotificationType.error,
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.download,
                color: AppColors.onScaffold(context),
              ),
              title: Text(
                '下载',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(downloadSongProvider)(item);
              },
            ),
          ],
        ),
      ),
    );
  }
}
