import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../playlist/presentation/playlist_picker.dart';
import '../../download/presentation/download_provider.dart';
import 'search_controls.dart';
import 'search_provider.dart';
import 'song_list_detail_screen.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/favorite_button.dart';
import 'package:animations/animations.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../core/widgets/loading_widget.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    this.autofocusDelay,
    this.canAutofocus,
    this.embedded = false,
    this.reserveKeyboardInset = true,
    this.onDismiss,
  });

  /// 进入后延迟聚焦输入框并弹出输入法。
  /// 首页搜索弹窗在滑入 2/3 时聚焦；独立搜索页立即聚焦。
  final Duration? autofocusDelay;

  /// 嵌在搜索弹窗内时不要再铺实色底，让外层磨砂透出来。
  final bool embedded;

  /// 内容底部是否为输入法留白。搜索弹窗会让面板整体缩到键盘上沿，
  /// 此时再垫一层就是双倍空白；独立页面则需要它。
  final bool reserveKeyboardInset;

  /// 嵌在弹窗里时，由弹窗提供「带下滑动画的关闭」；独立页面直接 pop 路由。
  final Future<void> Function()? onDismiss;

  /// Sheet dismissal can begin while the delayed focus retry is still pending.
  /// The caller can veto focus to avoid re-opening the iOS keyboard mid-close.
  final bool Function()? canAutofocus;

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
        if (mounted && _canAutofocus) _searchFocus.requestFocus();
      });
    } else {
      _autofocusTimer = Timer(delay, () {
        if (!mounted || !_canAutofocus) return;
        _searchFocus.requestFocus();
        // 部分平台在 ModalBottomSheet 完成转场的同一帧会清掉焦点，
        // 再确认一次，避免键盘弹出后立即消失。
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (mounted && _canAutofocus && !_searchFocus.hasFocus) {
            _searchFocus.requestFocus();
          }
        });
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

  bool get _canAutofocus => widget.canAutofocus?.call() ?? true;

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

    return Container(
      color: widget.embedded
          ? Colors.transparent
          : Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 禁止随键盘改 body 高度，避免首焦布局抖动导致输入法秒关。
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, allSources, selectedSourceId),
              Expanded(child: _buildMainContent(searchState, searchHistory)),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部输入条 + 音源切换。
  ///
  /// 竖屏分两层：胶囊输入行在上，平台胶囊在下。横屏可用高度只有三百多，
  /// 两层会把结果区挤没，改成一行内左右分栏，各自滚动。
  Widget _buildHeader(
    BuildContext context,
    List<SearchSourceItem> sources,
    String selectedSourceId,
  ) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > size.height * 1.15;
    final cancel = widget.embedded
        ? () {
            final dismiss = widget.onDismiss;
            if (dismiss != null) {
              unawaited(dismiss());
            } else {
              Navigator.maybePop(context);
            }
          }
        : null;

    final field = SearchFieldBar(
      controller: _searchController,
      focusNode: _searchFocus,
      hintText: S.of(context).searchFieldHint,
      autofocus: widget.autofocusDelay == null,
      clearTooltip: S.of(context).clearSearch,
      submitTooltip: S.of(context).searchAction,
      cancelLabel: S.of(context).cancel,
      // 横屏时取消按钮搬到行尾，让输入框和平台胶囊紧挨着。
      onCancel: wide ? null : cancel,
      onClear: () {
        _searchController.clear();
        ref.read(searchQueryProvider.notifier).state = '';
        ref.read(searchStateProvider.notifier).reset();
        setState(() {});
      },
      onSubmit: _onSearch,
    );
    final chips = SearchSourceChips(
      sources: sources,
      selectedId: selectedSourceId,
      padding: wide
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16),
      onSelected: (id) {
        ref.read(selectedSourceIdProvider.notifier).state = id;
        if (_searchController.text.isNotEmpty) {
          _onSearch(_searchController.text);
        }
      },
    );

    // 面板本身已经在滑入，控件再叠一次左右位移会显得手忙脚乱。这里只做
    // 6pt 上浮 + 淡入，让视线先落在「输入在哪」。
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motionDuration(context, const Duration(milliseconds: 320)),
      curve: MotionCurve.iosSpring,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - t)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 10),
        child: wide
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(flex: 5, child: field),
                    const SizedBox(width: 12),
                    Expanded(flex: 7, child: chips),
                    if (cancel != null) ...[
                      const SizedBox(width: 10),
                      SearchCancelButton(
                        label: S.of(context).cancel,
                        onTap: cancel,
                      ),
                    ],
                  ],
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: field,
                  ),
                  const SizedBox(height: 10),
                  chips,
                ],
              ),
      ),
    );
  }

  /// 输入法弹起后给列表尾部留出的空间，避免最后一行藏在键盘后面。
  double _keyboardInset(BuildContext context) =>
      widget.reserveKeyboardInset ? MediaQuery.viewInsetsOf(context).bottom : 0;

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    Widget? trailing,
  }) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.secondaryText(context),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
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
    // 用「已提交的关键词」而不是输入框内容判断：用户正在打字但还没提交
    // 时，下面仍然该是历史和热搜，而不是一块「没有结果」。
    if (searchState.items.isEmpty &&
        searchState.query.isEmpty &&
        !searchState.isLoading) {
      return _buildHistory(searchHistory);
    }
    if (searchState.isLoading && searchState.items.isEmpty) {
      // 横屏可用高度只有三百多，少放两行，别让骨架自己就溢出。
      final size = MediaQuery.sizeOf(context);
      final wide = size.width > size.height * 1.15;
      return _SearchSkeleton(
        key: const ValueKey('search-loading'),
        rows: wide ? 4 : 6,
      );
    }
    if (searchState.error != null && searchState.items.isEmpty) {
      return _SearchStatePanel(
        key: const ValueKey('search-error'),
        icon: Icons.cloud_off_rounded,
        tone: Theme.of(context).colorScheme.error,
        title: S.of(context).searchErrorTitle,
        hint: S.of(context).searchFailed(searchState.error ?? ''),
        action: _PanelAction(
          label: S.of(context).retry,
          onTap: () =>
              ref.read(searchStateProvider.notifier).search(searchState.query),
        ),
      );
    }
    return _buildResultList(searchState);
  }

  Widget _buildResultList(SearchState searchState) {
    final results = searchState.items;
    final localMatches = searchState.localMatches;
    // 结果标题里把命中的关键词挑出来高亮。
    final query = searchState.query;
    // 页面级一次性读取收藏集合，避免每个可见行创建异步收藏查询。
    final favoriteSongs =
        ref.watch(favoriteSongsProvider).valueOrNull ?? const <MusicItem>[];
    if (results.isEmpty && localMatches.isEmpty && !searchState.isLoading) {
      // 只在「当前不是全网」时才给换源入口：停在全网还提示切全网是废话。
      final canSwitchSource =
          searchState.sourceId.isNotEmpty && searchState.sourceId != 'all';
      return _SearchStatePanel(
        key: const ValueKey('search-empty'),
        icon: Icons.search_off_rounded,
        title: S.of(context).searchEmptyTitle(searchState.query),
        hint: S.of(context).searchEmptyHint,
        action: canSwitchSource
            ? _PanelAction(
                label: S.of(context).searchAllSources,
                onTap: () {
                  ref.read(selectedSourceIdProvider.notifier).state = 'all';
                  _onSearch(searchState.query);
                },
              )
            : null,
      );
    }
    if (MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height) {
      return _buildLandscapeResultList(searchState, favoriteSongs);
    }
    final hasOnlineResults =
        results.isNotEmpty &&
        searchState.sourceId != 'local' &&
        searchState.sourceId != 'favorites';
    return CustomScrollView(
      key: ValueKey('results-${searchState.generation}'),
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      slivers: [
        if (localMatches.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _ResultSection(
              icon: Icons.library_music_rounded,
              label: S.of(context).localMusic,
              count: localMatches.length,
              accent: true,
            ),
          ),
          SliverList.builder(
            itemCount: localMatches.length,
            itemBuilder: (context, index) => _buildLocalSearchResult(
              localMatches[index],
              localMatches,
              divider: index < localMatches.length - 1,
            ),
          ),
        ],
        if (hasOnlineResults)
          SliverToBoxAdapter(
            child: _ResultSection(
              icon: Icons.cloud_queue_rounded,
              label: S.of(context).onlineMusic,
              count: results.length,
              accent: false,
            ),
          ),
        SliverList.builder(
          itemCount: results.length,
          itemBuilder: (context, index) => _buildOnlineSearchResult(
            results[index],
            results,
            favoriteSongs,
            divider: index < results.length - 1,
            query: query,
          ),
        ),
        if (searchState.hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: searchState.isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: AppLoadingIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.accentOf(context),
                          ),
                        ),
                      )
                    : Text(
                        S.of(context).slideForMore,
                        style: TextStyle(
                          color: AppColors.mutedText(context),
                          fontSize: 12,
                        ),
                      ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: 12 + _keyboardInset(context)),
        ),
      ],
    );
  }

  /// 横屏用多列网格：单列在 844pt 宽下每行会被拉得很空，多列更紧凑。
  ///
  /// 列数按面板的实际宽度算。桌面 1280 的屏幕里弹窗只有 820 宽，用屏幕
  /// 宽度算会排成四列，标题被压到只剩几个像素。
  Widget _buildLandscapeResultList(
    SearchState searchState,
    List<MusicItem> favoriteSongs,
  ) {
    final localMatches = searchState.localMatches;
    final results = searchState.items;
    final hasOnlineResults =
        results.isNotEmpty &&
        searchState.sourceId != 'local' &&
        searchState.sourceId != 'favorites';

    return LayoutBuilder(
      builder: (context, constraints) {
        // 每列至少分到 250pt，标题才有地方放。
        final columns = (constraints.maxWidth / 250).floor().clamp(2, 4);
        final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          // 72 是两行 ListTile 的最小高度；压到 66 会让每一格底部溢出。
          mainAxisExtent: 72,
          crossAxisSpacing: 10,
          mainAxisSpacing: 0,
        );
        return CustomScrollView(
          key: ValueKey('results-${searchState.generation}'),
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            if (localMatches.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _ResultSection(
                  icon: Icons.library_music_rounded,
                  label: S.of(context).localMusic,
                  count: localMatches.length,
                  accent: true,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemCount: localMatches.length,
                  itemBuilder: (context, index) => _buildLocalSearchResult(
                    localMatches[index],
                    localMatches,
                    compact: true,
                    query: searchState.query,
                  ),
                ),
              ),
            ],
            if (hasOnlineResults)
              SliverToBoxAdapter(
                child: _ResultSection(
                  icon: Icons.cloud_queue_rounded,
                  label: S.of(context).onlineMusic,
                  count: results.length,
                  accent: false,
                ),
              ),
            if (results.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemCount: results.length,
                  itemBuilder: (context, index) => _buildOnlineSearchResult(
                    results[index],
                    results,
                    favoriteSongs,
                    compact: true,
                    query: searchState.query,
                  ),
                ),
              ),
            if (searchState.hasMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: searchState.isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: AppLoadingIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.accentOf(context),
                              ),
                            ),
                          )
                        : Text(
                            S.of(context).slideForMore,
                            style: TextStyle(
                              color: AppColors.mutedText(context),
                              fontSize: 12,
                            ),
                          ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(height: 12 + _keyboardInset(context)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocalSearchResult(
    MusicItem local,
    List<MusicItem> localMatches, {
    bool divider = false,
    bool compact = false,
    String query = '',
  }) {
    void play() {
      // 选中结果就该收起键盘：输入法留着只会挡住接下来要看的内容。
      FocusManager.instance.primaryFocus?.unfocus();
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
    }

    if (compact) {
      return _CompactResultTile(
        item: local,
        query: query,
        isSonglist: false,
        isFavorite: false,
        showFavorite: false,
        onTap: play,
        onMore: () => _showSongMenu(local, localMatches),
      );
    }
    return _ResultRowShell(
      showDivider: divider,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 7,
        onTap: play,
        onLongPress: () => _showSongMenu(local, localMatches),
        leading: _ArtworkTile(
          artwork: local.artwork,
          size: 46,
          fallbackIcon: Icons.audiotrack_rounded,
        ),
        title: _HighlightedText(
          text: local.name,
          query: query,
          style: TextStyle(
            color: AppColors.onScaffold(context),
            fontSize: 14.5,
            height: 1.25,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
          ),
        ),
        subtitle: Text(
          S.of(context).localArtist(local.singer),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.mutedText(context),
            fontSize: 12,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineSearchResult(
    MusicItem item,
    List<MusicItem> results,
    List<MusicItem> favoriteSongs, {
    bool divider = false,
    bool compact = false,
    String query = '',
  }) {
    final isSonglist = !item.isPlayable;
    void open() {
      FocusManager.instance.primaryFocus?.unfocus();
      if (isSonglist) {
        Navigator.push(
          context,
          reduceMotion(context)
              ? PageRouteBuilder<void>(
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  pageBuilder: (_, _, _) =>
                      SongListDetailScreen(songList: item),
                )
              : MaterialPageRoute<void>(
                  builder: (_) => SongListDetailScreen(songList: item),
                ),
        );
        return;
      }
      final playable = results.where((e) => e.isPlayable).toList();
      final index = playable.indexWhere(
        (e) => e.identityKey == item.identityKey,
      );
      ref
          .read(playerServiceProvider)
          .setQueue(
            playable,
            startIndex: index < 0 ? 0 : index,
            manualPlayName: item.name,
          );
    }

    final menu = isSonglist
        ? null
        : () =>
              _showSongMenu(item, results.where((e) => e.isPlayable).toList());

    if (compact) {
      return _CompactResultTile(
        item: item,
        query: query,
        isSonglist: isSonglist,
        isFavorite: isFavoriteMusic(item, favoriteSongs),
        showFavorite: !isSonglist,
        onTap: open,
        onMore: menu,
      );
    }
    return _ResultRowShell(
      showDivider: divider,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 7,
        onTap: open,
        onLongPress: menu,
        leading: _ArtworkTile(
          artwork: item.artwork,
          size: 46,
          fallbackIcon: isSonglist
              ? Icons.queue_music_rounded
              : Icons.music_note_rounded,
        ),
        title: _HighlightedText(
          text: item.name,
          query: query,
          style: TextStyle(
            color: AppColors.onScaffold(context),
            fontSize: 14.5,
            height: 1.25,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
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
            height: 1.3,
          ),
        ),
        trailing: isSonglist
            ? Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.mutedText(context),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FavoriteButton(
                    song: item,
                    isFavorite: isFavoriteMusic(item, favoriteSongs),
                  ),
                  FxIconButton(
                    tooltip: S.of(context).moreActions,
                    padding: const EdgeInsets.all(8),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: AppColors.mutedText(context),
                      size: 19,
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
  }

  Widget _buildHistory(List<String> searchHistory) {
    final hotAsync = ref.watch(hotSearchProvider);

    return ListView(
      // 底部已由 MainScaffold 预留，勿再垫 100 造成空白层
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        if (searchHistory.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            S.of(context).searchHistory,
            trailing: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => ref.read(searchHistoryProvider.notifier).clear(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    S.of(context).clearHistory,
                    style: TextStyle(
                      color: AppColors.secondaryText(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in searchHistory)
                _HistoryChip(
                  label: keyword,
                  onTap: () {
                    _searchController.text = keyword;
                    _onSearch(keyword);
                  },
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        _buildSectionHeader(context, S.of(context).hotSearch),
        const SizedBox(height: 2),
        hotAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              S.of(context).loadingEllipsis,
              style: TextStyle(
                color: AppColors.mutedText(context),
                fontSize: 13,
              ),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (hots) => Column(
            children: [
              for (var i = 0; i < hots.length; i++)
                _HotRow(
                  index: i,
                  label: hots[i],
                  last: i == hots.length - 1,
                  onTap: () {
                    _searchController.text = hots[i];
                    _onSearch(hots[i]);
                  },
                ),
            ],
          ),
        ),
        SizedBox(height: _keyboardInset(context)),
      ],
    );
  }

  void _showSongMenu(dynamic item, List playableItems) {
    showKoyzeSheet(
      context: context,
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
                S.of(context).playNow,
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
                S.of(context).addToPlaylist,
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
                S.of(context).favorite,
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(toggleFavoriteProvider)(item);
                } catch (error) {
                  if (!mounted) return;
                  showAppNotification(
                    '${S.of(context).favoriteFailed}: $error',
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
                S.of(context).download,
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

/// 结果分组标题：小图标 + 名称 + 数量。
///
/// 原来用「———— 在线音乐 ————」两头拉线的写法，在磨砂面板上会画出两条
/// 突兀的实线；改成左对齐的小标签后，分组层级靠字重和色阶表达。
class _ResultSection extends StatelessWidget {
  const _ResultSection({
    required this.icon,
    required this.label,
    required this.count,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? AppColors.accentOf(context)
        : AppColors.secondaryText(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              height: 1.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: AppColors.mutedText(context).withValues(alpha: 0.7),
              fontSize: 11,
              height: 1.0,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 结果行的分隔线外壳。线从封面右侧起笔，和 iOS 分组列表一致。
class _ResultRowShell extends StatelessWidget {
  const _ResultRowShell({required this.child, required this.showDivider});

  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        child,
        if (showDivider)
          Divider(
            height: 0.6,
            thickness: 0.6,
            indent: 78,
            endIndent: 16,
            color: AppColors.cardBorder(context).withValues(alpha: 0.65),
          ),
      ],
    );
  }
}

/// 方形封面。没有封面时用一档浅填充 + 图标，而不是纯色块。
class _ArtworkTile extends StatelessWidget {
  const _ArtworkTile({
    required this.artwork,
    required this.size,
    required this.fallbackIcon,
  });

  final String? artwork;
  final double size;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    final hasArtwork = artwork != null && artwork!.isNotEmpty;
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.fill2(context),
            borderRadius: radius,
            border: Border.all(
              color: AppColors.cardBorder(context).withValues(alpha: 0.7),
              width: 0.6,
            ),
          ),
          child: hasArtwork
              ? ArtworkImage(
                  artwork!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _fallback(context),
                )
              : _fallback(context),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) => Center(
    child: Icon(
      fallbackIcon,
      size: size * 0.42,
      color: AppColors.mutedText(context),
    ),
  );
}

/// 搜索历史胶囊。Material 的 ActionChip 自带一层灰底和 8pt 圆角，夹在
/// 玻璃面板里像一个外来控件，这里改成与平台胶囊同族的写法。
class _HistoryChip extends StatelessWidget {
  const _HistoryChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final primary = AppColors.onScaffold(context);
    final borderRadius = BorderRadius.circular(17);
    return Material(
      color: primary.withValues(alpha: isDark ? 0.07 : 0.05),
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // 用纵向内边距撑高而不是 height + alignment：后者会让胶囊在
          // Wrap 里占到整行宽。
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: AppColors.cardBorder(context),
              width: 0.7,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: primary.withValues(alpha: 0.88),
              fontSize: 13,
              height: 1.0,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// 热搜行。前三名用强调色 + 更重的字重，其余回落到主文字色阶，靠数字
/// 列对齐形成节奏，不额外加徽标。
class _HotRow extends StatelessWidget {
  const _HotRow({
    required this.index,
    required this.label,
    required this.last,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.onScaffold(context);
    final top = index < 3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 46,
          child: Stack(
            children: [
              // 分隔线从榜名那一列起，而不是横贯整块面板：七条通栏线会把
              // 热搜压成一张表格，序号和名字之间的留白也被切断。
              if (!last)
                Positioned(
                  left: 32,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 0.6,
                    child: ColoredBox(
                      color: AppColors.cardBorder(
                        context,
                      ).withValues(alpha: 0.55),
                    ),
                  ),
                ),
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: top
                            ? AppColors.accentOf(context)
                            : primary.withValues(alpha: 0.72),
                        fontSize: top ? 15 : 14,
                        height: 1.0,
                        fontWeight: top ? FontWeight.w800 : FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primary.withValues(alpha: 0.92),
                        fontSize: 14.5,
                        height: 1.0,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 横屏网格用的紧凑结果行。
///
/// 同样的内容交给 [ListTile]，在 72pt 高的格子里会被 leading + trailing
/// 抢走大部分宽度，标题被压成 0 宽直接看不见。这里用 Row 自己排版：
/// 封面固定、标题吃掉剩余空间、动作按钮固定宽度。
class _CompactResultTile extends StatelessWidget {
  const _CompactResultTile({
    required this.item,
    required this.query,
    required this.isSonglist,
    required this.isFavorite,
    required this.showFavorite,
    required this.onTap,
    required this.onMore,
  });

  final MusicItem item;
  final String query;
  final bool isSonglist;
  final bool isFavorite;
  final bool showFavorite;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final subtitle = isSonglist
        ? item.singer
        : '${item.singer}${item.album.isNotEmpty ? ' · ${item.album}' : ''}';
    return InkWell(
      onTap: onTap,
      onLongPress: onMore,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            _ArtworkTile(
              artwork: item.artwork,
              size: 40,
              fallbackIcon: isSonglist
                  ? Icons.queue_music_rounded
                  : Icons.music_note_rounded,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightedText(
                    text: item.name,
                    query: query,
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 13.5,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            if (isSonglist)
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.mutedText(context),
              )
            else ...[
              if (showFavorite)
                FavoriteButton(
                  song: item,
                  isFavorite: isFavorite,
                  iconSize: 20,
                ),
              FxIconButton(
                tooltip: S.of(context).moreActions,
                padding: const EdgeInsets.all(6),
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.mutedText(context),
                  size: 18,
                ),
                onPressed: onMore,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 把标题里命中搜索词的部分染成强调色。
///
/// 只做不区分大小写的子串匹配：搜索源返回的标题与用户输入未必同大小写，
/// 但字符顺序一致，逐个切片比拼正则更省事，也不用转义用户输入。
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
  });

  final String text;
  final String query;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final haystack = text.toLowerCase();
    if (needle.isEmpty || !haystack.contains(needle)) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final accent = AppColors.accentOf(context);
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final hit = haystack.indexOf(needle, cursor);
      if (hit < 0) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (hit > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, hit)));
      }
      final end = (hit + needle.length).clamp(hit, text.length);
      spans.add(
        TextSpan(
          text: text.substring(hit, end),
          style: TextStyle(color: accent, fontWeight: FontWeight.w700),
        ),
      );
      cursor = end;
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 加载骨架：按真实结果行的骨架屏，比一个转圈更能说明「马上就有列表了」。
///
/// 整块共用一个 `AnimationController`，微光横扫由它驱动；行与行之间靠
/// 递减的不透明度拉开层次，让人一眼看出列表在往下延伸。
class _SearchSkeleton extends StatefulWidget {
  const _SearchSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  State<_SearchSkeleton> createState() => _SearchSkeletonState();
}

class _SearchSkeletonState extends State<_SearchSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );
  var _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = reduceMotion(context);
    if (reduce == _reduced && (_reduced || _sweep.isAnimating)) return;
    _reduced = reduce;
    if (reduce) {
      // 减弱动效时不跑循环，停在中段让微光均匀分布。
      _sweep
        ..stop()
        ..value = 0.5;
    } else {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  // 每行长度固定不随机：骨架屏自己跳动比没有骨架还干扰。
  static const _titleFactors = [0.62, 0.48, 0.71, 0.54, 0.66, 0.44];
  static const _subFactors = [0.30, 0.24, 0.36, 0.27, 0.32, 0.22];

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final base = dark ? const Color(0xFF34343A) : const Color(0xFFDFDFE5);
    final glow = dark ? const Color(0xFF52525C) : const Color(0xFFFFFFFF);
    return AnimatedBuilder(
      animation: _sweep,
      // 子项只画实心块，颜色全交给遮罩上的横向渐变：整片列表共用一条扫光。
      // 让每个方块自带渐变的话，同一时刻每个块都亮在自己身上，看起来像一堆
      // 并排的斜纹，而不是一道光扫过列表。
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        itemCount: widget.rows,
        itemBuilder: (context, index) => _SkeletonRow(
          titleFactor: _titleFactors[index % _titleFactors.length],
          subFactor: _subFactors[index % _subFactors.length],
          opacity: (1 - index * 0.09).clamp(0.56, 1.0),
        ),
      ),
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          // -0.25 → 1.25：光带从面板左外侧扫到右外侧，两端各留一段空转。
          final center = -0.25 + _sweep.value * 1.5;
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [base, base, glow, base, base],
            stops: [
              0,
              (center - 0.15).clamp(0.0, 1.0),
              center.clamp(0.0, 1.0),
              (center + 0.15).clamp(0.0, 1.0),
              1,
            ],
          ).createShader(rect);
        },
        child: child,
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({
    required this.titleFactor,
    required this.subFactor,
    required this.opacity,
  });

  final double titleFactor;
  final double subFactor;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Padding(
        // 与真实结果行同一条 gutter，加载态到结果态不会左右跳一下。
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBar(widthFactor: titleFactor, height: 11),
                  const SizedBox(height: 8),
                  _SkeletonBar(widthFactor: subFactor, height: 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 按父级宽度的比例取长的骨架条。填充色是「占位符」，真实颜色来自外层
/// `ShaderMask` 的扫光，所以这里统一用不透明白。
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }
}

/// 空结果 / 出错的统一版式：柔光徽标 + 标题 + 说明 + 可选动作。
class _SearchStatePanel extends StatelessWidget {
  const _SearchStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.tone,
    this.action,
  });

  final IconData icon;
  final String title;
  final String hint;
  final Color? tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final accent = tone ?? AppColors.accentOf(context);
    return Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(30, 10, 30, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.18),
                    accent.withValues(alpha: 0.04),
                  ],
                ),
                border: Border.all(
                  color: accent.withValues(alpha: 0.22),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.10),
                    blurRadius: 18,
                    spreadRadius: -6,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(icon, size: 25, color: accent.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.onScaffold(context),
                fontSize: 15,
                height: 1.3,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.mutedText(context),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// 状态面板里的动作按钮。
///
/// 面板里只有一个动作，用实心 accent 胶囊给足点击优先级；淡底 + accent 字的
/// 淡描边在浅色主题里对比度只有 2.5:1，看着像禁用态。
class _PanelAction extends StatelessWidget {
  const _PanelAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    // 不直接用 colorScheme.onPrimary：浅色主题里它是白色，压在这个绿上只有
    // 2.4:1 对比度。按 accent 的明度自己挑墨色，换任何强调色都不会糊。
    final ink = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : const Color(0xFF08130C);
    final radius = BorderRadius.circular(999);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: accent,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 14,
                spreadRadius: -4,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                color: ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
