import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_strings.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/frosted_tab_header.dart';
import '../../../core/widgets/root_shell_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../../../core/widgets/card_play_button.dart';
import '../../../core/widgets/origo_chrome.dart';
import '../domain/playlist.dart';
import '../domain/playlist_import_service.dart';
import '../domain/playlist_service.dart';
import '../../player/domain/music_item.dart';
import 'playlist_provider.dart';
import '../../player/presentation/player_provider.dart';
import '../../recommend/presentation/recommendation_provider.dart';
import '../../nas/domain/nas_kind.dart';
import '../../nas/presentation/nas_provider.dart';
import '../../subsonic/presentation/subsonic_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/koyze_modal.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../core/widgets/loading_widget.dart';

enum PlaylistSortMode { recent, name, songCount }

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key});

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  PlaylistSortMode _sortMode = PlaylistSortMode.recent;

  String get _searchQuery => _searchController.text;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Playlist> _filterAndSort(List<Playlist> playlists) {
    // 系统歌单：我喜欢 / 最近播放 / 本地音乐 单独展示，不进普通列表
    var filtered = playlists
        .where(
          (p) => p.id != 'favorites' && p.id != 'recent' && p.id != 'local',
        )
        .toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((p) {
        if (p.name.toLowerCase().contains(q)) return true;
        if ((p.description ?? '').toLowerCase().contains(q)) return true;
        return false;
      }).toList();
    }

    switch (_sortMode) {
      case PlaylistSortMode.name:
        filtered.sort((a, b) => a.name.compareTo(b.name));
      case PlaylistSortMode.songCount:
        filtered.sort((a, b) => b.songCount.compareTo(a.songCount));
      case PlaylistSortMode.recent:
        break;
    }

    return filtered;
  }

  /// 在库中按歌曲搜索：返回 (playlist, song, index)
  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    ref.watch(playlistRecentRevisionProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final favorites = playlistService.favorites;
    final recent = playlistService.recent;
    final local = playlistService.local;
    final playerService = ref.watch(playerServiceProvider);
    final filteredPlaylists = _filterAndSort(playlists);
    final songSearch = _searchQuery.isEmpty
        ? null
        : ref.watch(playlistSongSearchProvider(_searchQuery));
    final songHits = songSearch?.valueOrNull ?? const <PlaylistSongMatch>[];

    final bodyItems = _bodyItems(
      songHits: songHits,
      filteredPlaylists: filteredPlaylists,
      isLoading: songSearch?.isLoading ?? false,
    );
    final isLandscapeShell = RootShellLayout.usesSideNavigationOf(context);
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 主壳已固定预留底部导航和迷你播放器；键盘直接覆盖它们，避免重复预留空白。
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            // 只发布标题：顶栏由根壳层渲染，切 tab 时不会跟着页面走。
            // 这个页面是 Column 布局而不是 Stack，所以要显式让出栏的高度。
            RootHeaderPublisher(
              index: 2,
              title: S.of(context).playlists,
              actions: [
                FrostedHeaderButton(
                  icon: Icons.playlist_add_rounded,
                  semanticLabel: S.of(context).importPlaylist,
                  onTap: () => _showImportDialog(context, ref),
                ),
              ],
            ),
            if (!isLandscapeShell)
              SizedBox(height: FrostedTabHeader.extent(context)),
            Expanded(
              child: ShellContentFrame(
                child: Column(
                  children: [
                    Padding(
                      // 与卡片左边缘同一条线（16），上下的呼吸量也收在同一档，
                      // 搜索条不再像被随手贴在标题下面。
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: SizedBox(
                        height: 46,
                        child: OrigoChromeSurface(
                          borderRadius: BorderRadius.circular(16),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          // 首页的搜索入口是一条玻璃条；这里原本是实心灰块，
                          // 同一应用里两种搜索入口长得不一样，翻页时很跳。
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 19,
                                color: AppColors.secondaryText(context),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocus,
                                  style: TextStyle(
                                    color: AppColors.onScaffold(context),
                                    fontSize: 14,
                                  ),
                                  // 延迟过滤，避免每个字符整页 rebuild 抢焦点
                                  onChanged: (_) {
                                    Future.microtask(() {
                                      if (mounted) setState(() {});
                                    });
                                  },
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    // 必须是显式 false：InputDecoration 的
                                    // filled 为 null 时会回填主题里的
                                    // filled:true，于是在玻璃条中间又糊出一块
                                    // 实心 surface（浅色主题下是白色）。
                                    filled: false,
                                    isCollapsed: true,
                                    // 光改 border 不够：主题给 enabledBorder 描了
                                    // 一圈 outlineVariant，TextField 会用它。
                                    // 外层玻璃条已经是这条搜索框的边界，里面再
                                    // 描一圈就是「框里套框」。
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: S.of(context).searchLibraryHint,
                                    hintStyle: TextStyle(
                                      color: AppColors.secondaryText(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                FxIconButton(
                                  tooltip: S.of(context).clearSearch,
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 17,
                                    color: AppColors.secondaryText(context),
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          RootShellLayout.obscuredBottomOf(context),
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: bodyItems.length,
                        itemBuilder: (context, index) => _buildBodyItem(
                          context,
                          ref,
                          playerService,
                          bodyItems[index],
                          favorites: favorites,
                          local: local,
                          recent: recent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPlaylist(
    BuildContext context,
    Playlist playlist, {
    String? focusSongId,
  }) {
    context.pushNamed(
      'playlistDetail',
      pathParameters: {'playlistId': playlist.id},
      queryParameters: {if (focusSongId != null) 'focusSongId': focusSongId},
    );
  }

  Future<void> _playPlaylist(
    dynamic playerService,
    Playlist playlist, {
    int startIndex = 0,
  }) async {
    try {
      if (playlist.songCount <= 0) return;
      await playerService.playPagedPlaylist(
        songCount: playlist.songCount,
        startIndex: startIndex,
        playlistId: playlist.id,
        manual: true,
        loadPage: (offset, limit) async {
          final page = await ref
              .read(playlistServiceProvider)
              .getSongsPage(playlist.id, offset: offset, limit: limit);
          return page.songs;
        },
      );
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        '${S.of(context).loadSongsFailed}: $error',
        type: AppNotificationType.error,
      );
    }
  }

  /// 列表项的轻量描述：只有 itemBuilder 真正命中时才会构建对应 widget，
  /// 屏幕外的歌单/歌曲搜索命中不会被渲染。
  List<_PlaylistBodyItem> _bodyItems({
    required List<PlaylistSongMatch> songHits,
    required List<Playlist> filteredPlaylists,
    required bool isLoading,
  }) {
    if (_searchQuery.isEmpty) {
      return [
        const _BodyPresetGrid(),
        const _BodyGap(24),
        _BodyHeader(title: S.of(context).customPlaylists, trailing: true),
        const _BodyGap(12),
        for (final playlist in filteredPlaylists) _BodyPlaylistItem(playlist),
      ];
    }
    final items = <_PlaylistBodyItem>[
      if (isLoading) const _BodyLoading(),
      if (songHits.isNotEmpty) ...[
        _BodyHeader(
          title: S.of(context).songsHeader(songHits.length),
          trailing: false,
        ),
        const _BodyGap(8),
        for (final hit in songHits) _BodySongHitItem(hit),
        const _BodyGap(16),
      ],
      if (filteredPlaylists.isNotEmpty) ...[
        _BodyHeader(
          title: S.of(context).playlistsHeader(filteredPlaylists.length),
          trailing: false,
        ),
        const _BodyGap(8),
        for (final playlist in filteredPlaylists) _BodyPlaylistItem(playlist),
      ],
      if (songHits.isEmpty && filteredPlaylists.isEmpty)
        const _BodyEmptyResult(),
    ];
    final size = MediaQuery.sizeOf(context);
    if (size.width <= size.height) return items;
    final rows = <_PlaylistBodyItem>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item is! _BodySongHitItem) {
        rows.add(item);
        continue;
      }
      final second =
          index + 1 < items.length && items[index + 1] is _BodySongHitItem
          ? (items[++index] as _BodySongHitItem).hit
          : null;
      rows.add(_BodySongHitPair(item.hit, second));
    }
    return rows;
  }

  Widget _buildBodyItem(
    BuildContext context,
    WidgetRef ref,
    dynamic playerService,
    _PlaylistBodyItem item, {
    required Playlist? favorites,
    required Playlist? local,
    required Playlist? recent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return switch (item) {
      _BodyPresetGrid() => _buildPresetGrid(
        context,
        ref,
        playerService,
        favorites: favorites,
        local: local,
        recent: recent,
      ),
      _BodyGap(:final height) => SizedBox(height: height),
      _BodyHeader(:final title, :final trailing) => Row(
        children: [
          // 与首页「快捷方式」同一档：二级分区名是标签，不是第二个页面标题。
          // 原来 16pt 常白加粗，比卡片里的歌单名还重，层级是反的。
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: AppColors.secondaryText(context),
            ),
          ),
          const Spacer(),
          if (trailing) ...[
            FxIconButton(
              tooltip: S.of(context).newPlaylist,
              // IconButton 的 48 命中区里图标只占中间一圈，视觉边缘会内缩
              // 十几 pt，右侧两个按钮因此对不上卡片的右边线。
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(
                Icons.add_rounded,
                color: AppColors.secondaryText(context),
                size: 21,
              ),
              onPressed: () => _showCreateDialog(context, ref),
            ),
            const SizedBox(width: 2),
            FxIconButton(
              tooltip: S.of(context).sortPlaylists,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(
                Icons.sort_rounded,
                color: AppColors.secondaryText(context),
                size: 19,
              ),
              onPressed: () => _showSortMenu(context),
            ),
          ],
        ],
      ),
      _BodyPlaylistItem(:final playlist) => _buildPlaylistItem(
        context,
        ref,
        playlist,
      ),
      _BodySongHitItem(:final hit) => _buildSongHitItem(
        context,
        ref,
        hit.playlist,
        hit.song,
        hit.index,
        playerService,
      ),
      _BodySongHitPair(:final first, :final second) => Row(
        children: [
          Expanded(
            child: _buildSongHitItem(
              context,
              ref,
              first.playlist,
              first.song,
              first.index,
              playerService,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: second == null
                ? const SizedBox.shrink()
                : _buildSongHitItem(
                    context,
                    ref,
                    second.playlist,
                    second.song,
                    second.index,
                    playerService,
                  ),
          ),
        ],
      ),
      _BodyLoading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: AppLoadingIndicator()),
      ),
      _BodyEmptyResult() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            S.of(context).nothingMatched,
            style: TextStyle(color: scheme.onSurface.withAlpha(120)),
          ),
        ),
      ),
    };
  }

  Widget _buildSongHitItem(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    MusicItem song,
    int index,
    dynamic playerService,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassSurface(
        style: AppGlassStyle.regular,
        borderRadius: BorderRadius.circular(16),
        border: Border.fromBorderSide(
          AppGlass.hairline(context, emphasized: false),
        ),
        child: ListTile(
          onTap: () => _openPlaylist(context, playlist, focusSongId: song.id),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: song.artwork != null && song.artwork!.isNotEmpty
                  ? ArtworkImage(
                      song.artwork!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.music_note,
                        color: AppColors.mutedText(context),
                      ),
                    )
                  : Icon(Icons.music_note, color: AppColors.mutedText(context)),
            ),
          ),
          title: Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.onScaffold(context),
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${song.singer} · ${S.of(context).builtinPlaylistName(playlist.id, playlist.name)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
          ),
          trailing: FxIconButton(
            icon: Icon(
              Icons.play_arrow_rounded,
              color: AppColors.accentOf(context),
            ),
            onPressed: () async {
              await _playPlaylist(playerService, playlist, startIndex: index);
            },
          ),
        ),
      ),
    );
  }

  /// 五个预设歌单。宽度够放两张时自动两列，窄屏仍是单列。
  Widget _buildPresetGrid(
    BuildContext context,
    WidgetRef ref,
    dynamic playerService, {
    required Playlist? favorites,
    required Playlist? local,
    required Playlist? recent,
  }) {
    final cards = <Widget>[
      _buildFavoritesCard(context, ref, favorites, playerService),
      _buildRecommendCard(context, ref, playerService),
      _buildLocalCard(context, ref, local, playerService),
      _buildSubsonicCard(context, ref, playerService),
      _buildRecentCard(context, ref, recent, playerService),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 480 ? 2 : 1;
        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cards[i],
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 12),
              Row(
                // 入口数是奇数，最后一行只剩一张。用 SizedBox.shrink 占住
                // 右半格会在页面底部留一个 300 宽的黑洞，不如让它铺满。
                children: [
                  Expanded(child: cards[i]),
                  if (i + 1 < cards.length) ...[
                    const SizedBox(width: 12),
                    Expanded(child: cards[i + 1]),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFavoritesCard(
    BuildContext context,
    WidgetRef ref,
    Playlist? favorites,
    dynamic playerService,
  ) {
    final songCount = favorites?.songCount ?? 0;
    return _PresetCard(
      icon: Icons.favorite_rounded,
      tone: const Color(0xFFFF453A),
      title: S.of(context).favorites,
      subtitle: S.of(context).songCount(songCount),
      onTap: () => context.pushNamed(
        'playlistDetail',
        pathParameters: {'playlistId': 'favorites'},
      ),
      onPlay: favorites != null && favorites.songCount > 0
          ? () => _playPlaylist(playerService, favorites)
          : null,
    );
  }

  Widget _buildRecentCard(
    BuildContext context,
    WidgetRef ref,
    Playlist? recent,
    dynamic playerService,
  ) {
    final songCount = recent?.songCount ?? 0;
    return _PresetCard(
      icon: Icons.history_rounded,
      tone: const Color(0xFF3E8BFF),
      title: S.of(context).recentPlays,
      subtitle: S.of(context).songCount(songCount),
      onTap: () => context.pushNamed(
        'playlistDetail',
        pathParameters: {'playlistId': 'recent'},
      ),
      onPlay: recent != null && recent.songCount > 0
          ? () => _playPlaylist(playerService, recent)
          : null,
    );
  }

  Widget _buildLocalCard(
    BuildContext context,
    WidgetRef ref,
    Playlist? local,
    dynamic playerService,
  ) {
    final songCount = local?.songCount ?? 0;
    return _PresetCard(
      icon: Icons.folder_rounded,
      tone: const Color(0xFFAF6BFF),
      title: S.of(context).localMusic,
      subtitle: songCount == 0
          ? S.of(context).chooseFolderToScan
          : S.of(context).songCount(songCount),
      onTap: () => context.pushNamed(
        'playlistDetail',
        pathParameters: {'playlistId': 'local'},
      ),
      onPlay: local != null && local.songCount > 0
          ? () => _playPlaylist(playerService, local)
          : null,
    );
  }

  Widget _buildRecommendCard(
    BuildContext context,
    WidgetRef ref,
    dynamic playerService,
  ) {
    final recommendationsAsync = ref.watch(recommendationProvider);
    final recommendations = recommendationsAsync.valueOrNull ?? const [];
    final count = recommendations.length;
    return _PresetCard(
      icon: Icons.auto_awesome_rounded,
      tone: const Color(0xFFFF9F2E),
      title: S.of(context).forYou,
      subtitle: count > 0
          ? S.of(context).recommendedSongs(count)
          : S.of(context).recommendAfterFavorites,
      onTap: () => context.push('/recommend'),
      onPlay: recommendations.isEmpty
          ? null
          : () => playerService.playPlaylist(
              recommendations.map((item) => item.song).toList(),
              manualPlayName: recommendations.first.song.name,
            ),
    );
  }

  Widget _buildSubsonicCard(BuildContext context, WidgetRef ref, dynamic _) {
    final subsonicConnected = ref.watch(subsonicConnectedProvider);
    final nasConnected = {
      for (final kind in NasKind.values)
        kind: ref.watch(nasConnectedProvider(kind)),
    };
    final connected =
        subsonicConnected || nasConnected.values.any((value) => value);
    final config = ref.watch(subsonicConfigProvider);
    final songsAsync = subsonicConnected
        ? ref.watch(subsonicLibrarySongsProvider)
        : const AsyncValue<List<MusicItem>>.data([]);
    final songs = songsAsync.valueOrNull ?? const <MusicItem>[];
    final songCount = songs.length;
    final subtitle = !connected
        ? S.of(context).nasHosts
        : subsonicConnected && songsAsync.isLoading
        ? S.of(context).loadingHost(config.hostLabel)
        : 'NAS';
    return _PresetCard(
      icon: Icons.cloud_queue_rounded,
      tone: const Color(0xFF38BDF8),
      title: S.of(context).nasLibrary,
      subtitle: subtitle,
      onTap: () => context.push('/subsonic'),
      onPlay: !subsonicConnected || songCount <= 0
          ? null
          : () => _playSubsonicLibrary(ref, songs),
    );
  }

  Future<void> _playSubsonicLibrary(
    WidgetRef ref,
    List<MusicItem> songs,
  ) async {
    try {
      var queue = songs;
      if (queue.isEmpty) {
        queue = await ref.read(subsonicServiceProvider).getLibrarySongs();
      }
      if (queue.isEmpty) {
        showAppNotification(
          S.of(context).noSongsOnServer,
          type: AppNotificationType.info,
        );
        return;
      }
      await ref
          .read(playerServiceProvider)
          .playPlaylist(queue, manualPlayName: queue.first.name);
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        '${S.of(context).playFailed}: $error',
        type: AppNotificationType.error,
      );
    }
  }

  Widget _buildPlaylistItem(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fill(context),
        // 与上方预设卡同一个圆角与行高（12 + 48 + 12 = 72）：
        // 两种条目交替出现时，行高差 8pt 会让整列基线看起来是歪的。
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Pressable(
        borderRadius: BorderRadius.circular(18),
        captureExpandRect: true,
        onTap: () {
          _openPlaylist(context, playlist);
        },
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withAlpha(100),
                    Theme.of(context).colorScheme.primary.withAlpha(40),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  // 空名歌单显示音符占位，避免 substring 崩溃。
                  playlist.name.isEmpty ? '♪' : playlist.name.substring(0, 1),
                  style: TextStyle(
                    color: AppColors.onScaffold(context),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S
                        .of(context)
                        .builtinPlaylistName(playlist.id, playlist.name),
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    S
                        .of(context)
                        .playlistMeta(playlist.songCount, playlist.description),
                    style: TextStyle(
                      color: AppColors.secondaryText(context),
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            FxIconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(
                Icons.more_vert_rounded,
                color: AppColors.secondaryText(context),
                size: 19,
              ),
              onPressed: () => _showPlaylistMoreMenu(context, ref, playlist),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final nameFocus = FocusNode();
    final descFocus = FocusNode();
    var keyboardRequested = false;

    showKoyzeDialog(
      context: context,
      builder: (dialogContext) {
        if (!keyboardRequested) {
          keyboardRequested = true;
          requestTextInput(
            dialogContext,
            nameFocus,
            initialDelay: const Duration(milliseconds: 280),
            retryDelay: const Duration(milliseconds: 220),
          );
        }
        return KoyzeDialog(
          backgroundColor: AppColors.dialogBg(dialogContext),
          title: Text(
            S.of(context).createPlaylist,
            style: TextStyle(color: AppColors.onScaffold(dialogContext)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                focusNode: nameFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => descFocus.requestFocus(),
                style: TextStyle(color: AppColors.onScaffold(dialogContext)),
                decoration: InputDecoration(
                  hintText: S.of(context).playlistName,
                  hintStyle: TextStyle(
                    color: AppColors.mutedText(dialogContext),
                  ),
                  filled: true,
                  fillColor: AppColors.fill2(dialogContext),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                focusNode: descFocus,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: AppColors.onScaffold(dialogContext)),
                decoration: InputDecoration(
                  hintText: S.of(context).descriptionOptional,
                  hintStyle: TextStyle(
                    color: AppColors.mutedText(dialogContext),
                  ),
                  filled: true,
                  fillColor: AppColors.fill2(dialogContext),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                S.of(dialogContext).cancel,
                style: TextStyle(color: AppColors.mutedText(dialogContext)),
              ),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    await ref.read(createPlaylistProvider)(
                      nameController.text,
                      description: descController.text.isEmpty
                          ? null
                          : descController.text,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (error) {
                    if (!dialogContext.mounted) return;
                    showAppNotification(
                      '${S.of(context).createFailed}: $error',
                      type: AppNotificationType.error,
                    );
                  }
                }
              },
              child: Text(
                S.of(dialogContext).create,
                style: TextStyle(color: AppColors.accentOf(dialogContext)),
              ),
            ),
          ],
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      descController.dispose();
      nameFocus.dispose();
      descFocus.dispose();
    });
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Playlist playlist) {
    final nameController = TextEditingController(text: playlist.name);
    final descController = TextEditingController(
      text: playlist.description ?? '',
    );
    final nameFocus = FocusNode();
    final descFocus = FocusNode();
    var keyboardRequested = false;

    showKoyzeDialog(
      context: context,
      builder: (ctx) {
        if (!keyboardRequested) {
          keyboardRequested = true;
          requestTextInput(
            ctx,
            nameFocus,
            initialDelay: const Duration(milliseconds: 280),
            retryDelay: const Duration(milliseconds: 220),
          );
        }
        return KoyzeDialog(
          backgroundColor: AppColors.dialogBg(ctx),
          title: Text(
            S.of(context).editPlaylist,
            style: TextStyle(color: AppColors.onScaffold(ctx)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                focusNode: nameFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => descFocus.requestFocus(),
                style: TextStyle(color: AppColors.onScaffold(ctx)),
                decoration: InputDecoration(
                  hintText: S.of(context).playlistName,
                  hintStyle: TextStyle(color: AppColors.mutedText(ctx)),
                  filled: true,
                  fillColor: AppColors.fill2(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                focusNode: descFocus,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: AppColors.onScaffold(ctx)),
                decoration: InputDecoration(
                  hintText: S.of(context).descriptionOptional,
                  hintStyle: TextStyle(color: AppColors.mutedText(ctx)),
                  filled: true,
                  fillColor: AppColors.fill2(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                S.of(ctx).cancel,
                style: TextStyle(color: AppColors.mutedText(ctx)),
              ),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    await ref
                        .read(playlistServiceProvider)
                        .updatePlaylist(
                          id: playlist.id,
                          name: nameController.text,
                          description: descController.text.isEmpty
                              ? null
                              : descController.text,
                        );
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (error) {
                    if (!ctx.mounted) return;
                    showAppNotification(
                      '${S.of(context).saveFailed}: $error',
                      type: AppNotificationType.error,
                    );
                  }
                }
              },
              child: Text(
                S.of(ctx).save,
                style: TextStyle(color: AppColors.accentOf(ctx)),
              ),
            ),
          ],
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      descController.dispose();
      nameFocus.dispose();
      descFocus.dispose();
    });
  }

  void _showSortMenu(BuildContext context) {
    showKoyzeSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KoyzeSheetGrabber(),
            KoyzeSheetTitle(
              title: S.of(context).sortBy,
              onClose: () => Navigator.pop(context),
            ),
            _sortOption(
              context,
              PlaylistSortMode.recent,
              Icons.schedule_rounded,
              S.of(context).recentlyAdded,
            ),
            _sortOption(
              context,
              PlaylistSortMode.name,
              Icons.sort_by_alpha_rounded,
              S.of(context).sortByName,
            ),
            _sortOption(
              context,
              PlaylistSortMode.songCount,
              Icons.music_note_rounded,
              S.of(context).sortByCount,
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(
    BuildContext context,
    PlaylistSortMode mode,
    IconData icon,
    String label,
  ) {
    final isSelected = _sortMode == mode;
    final accent = AppColors.accentOf(context);
    return KoyzeSheetAction(
      icon: icon,
      label: label,
      selected: isSelected,
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: accent, size: 20)
          : null,
      onTap: () {
        setState(() => _sortMode = mode);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final inputCtrl = TextEditingController();
    final inputFocus = FocusNode();
    var keyboardRequested = false;
    var platform = 'tx';
    var busy = false;
    String? error;
    // 网易云歌单需要分批拉取曲目详情，展示进度避免用户以为卡住。
    var progress = '';

    await showKoyzeDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        if (!keyboardRequested) {
          keyboardRequested = true;
          requestTextInput(
            ctx,
            inputFocus,
            initialDelay: const Duration(milliseconds: 280),
            retryDelay: const Duration(milliseconds: 220),
          );
        }
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return KoyzeDialog(
              backgroundColor: AppColors.dialogBg(context),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              clipBehavior: Clip.antiAlias,
              contentPadding: EdgeInsets.zero,
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: MediaQuery.sizeOf(ctx).height * .82,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Theme.of(ctx).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.playlist_add_rounded,
                              color: AppColors.accentOf(ctx),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  S.of(context).importPlaylist,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  S.of(context).pastePlaylistLink,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          FxIconButton(
                            tooltip: S.of(context).closeImport,
                            onPressed: busy ? null : () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * .48,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              S.of(context).sourcePlatform,
                              style: TextStyle(
                                color: AppColors.secondaryText(ctx),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: [
                                const ButtonSegment(
                                  value: 'tx',
                                  label: Text('QQ'),
                                  icon: Icon(Icons.music_note_rounded),
                                ),
                                ButtonSegment(
                                  value: 'kw',
                                  label: Text(S.of(context).kuwoShort),
                                  icon: const Icon(Icons.graphic_eq_rounded),
                                ),
                                ButtonSegment(
                                  value: 'kg',
                                  label: Text(S.of(context).kugouShort),
                                  icon: const Icon(Icons.headphones_rounded),
                                ),
                                ButtonSegment(
                                  value: 'wy',
                                  label: Text(S.of(context).neteaseShort),
                                  icon: const Icon(Icons.album_rounded),
                                ),
                              ],
                              selected: {platform},
                              showSelectedIcon: false,
                              onSelectionChanged: busy
                                  ? null
                                  : (value) =>
                                        setLocal(() => platform = value.first),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              S.of(context).playlistLinkOrId,
                              style: TextStyle(
                                color: AppColors.secondaryText(ctx),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: inputCtrl,
                              focusNode: inputFocus,
                              keyboardType: desktopSafeKeyboardType(
                                TextInputType.url,
                              ),
                              textInputAction: TextInputAction.done,
                              autocorrect: false,
                              enabled: !busy,
                              minLines: 2,
                              maxLines: 3,
                              style: TextStyle(
                                color: AppColors.onScaffold(ctx),
                              ),
                              decoration:
                                  InputDecoration(
                                    hintText: S.of(context).playlistLinkExample,
                                    alignLabelWithHint: true,
                                    prefixIcon: const Icon(Icons.link_rounded),
                                  ).applyDefaults(
                                    Theme.of(ctx).inputDecorationTheme,
                                  ),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    error!,
                                    style: const TextStyle(
                                      color: AppColors.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.cardBorder(ctx)),
                        ),
                        color: AppColors.dialogBg(ctx),
                      ),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: busy
                            ? null
                            : () async {
                                final input = inputCtrl.text.trim();
                                if (input.isEmpty) {
                                  setLocal(
                                    () => error = S.of(context).enterLinkOrId,
                                  );
                                  return;
                                }
                                setLocal(() {
                                  busy = true;
                                  error = null;
                                  progress = '';
                                });
                                try {
                                  final imported = await PlaylistImportService()
                                      .import(
                                        input: input,
                                        platformHint: platform,
                                        onProgress: (loaded, total) {
                                          if (!ctx.mounted) return;
                                          setLocal(() {
                                            progress = total > 0
                                                ? S
                                                      .of(context)
                                                      .importProgress(
                                                        loaded,
                                                        total,
                                                      )
                                                : '';
                                          });
                                        },
                                      );
                                  if (!ctx.mounted) return;
                                  final ok = await showKoyzeDialog<bool>(
                                    context: ctx,
                                    builder: (c2) => KoyzeDialog(
                                      backgroundColor: AppColors.dialogBg(
                                        context,
                                      ),
                                      title: Text(
                                        imported.name,
                                        style: TextStyle(
                                          color: AppColors.onScaffold(context),
                                        ),
                                      ),
                                      content: Text(
                                        S
                                            .of(context)
                                            .confirmImport(
                                              imported.songs.length,
                                            ),
                                        style: TextStyle(
                                          color: AppColors.mutedText(context),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c2, false),
                                          child: Text(
                                            S.of(context).cancel,
                                            style: TextStyle(
                                              color: AppColors.mutedText(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c2, true),
                                          child: Text(
                                            S.of(context).importAction,
                                            style: TextStyle(
                                              color: AppColors.accentOf(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await ref
                                        .read(playlistServiceProvider)
                                        .createPlaylist(
                                          name: imported.name,
                                          description: S
                                              .of(context)
                                              .importedFrom(imported.source),
                                          songs: imported.songs,
                                        );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (context.mounted) {
                                      showAppNotification(
                                        S
                                            .of(context)
                                            .importedResult(
                                              imported.name,
                                              imported.songs.length,
                                            ),
                                        type: AppNotificationType.success,
                                      );
                                    }
                                  } else {
                                    if (!ctx.mounted) return;
                                    setLocal(() => busy = false);
                                  }
                                } catch (e) {
                                  if (!ctx.mounted) return;
                                  setLocal(() {
                                    busy = false;
                                    error = e.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    );
                                  });
                                }
                              },
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: AppLoadingIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          busy
                              ? (progress.isEmpty
                                    ? S.of(context).parsingPlaylist
                                    : S.of(context).parsingProgress(progress))
                              : S.of(context).parsePlaylist,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      inputCtrl.dispose();
      inputFocus.dispose();
    });
  }

  void _showPlaylistMoreMenu(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.56;
    final maxW = media.size.width.clamp(280.0, 420.0).toDouble();

    showKoyzeDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final on = AppColors.onScaffold(context);
        final muted = AppColors.mutedText(context);
        Widget action({
          required IconData icon,
          required String label,
          required VoidCallback onTap,
          Color? color,
          bool destructive = false,
        }) {
          final c = color ?? (destructive ? AppColors.error : on);
          return Pressable(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: c, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: c,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return KoyzeDialog(
          maxWidth: maxW,
          contentPadding: EdgeInsets.zero,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          S
                              .of(context)
                              .builtinPlaylistName(playlist.id, playlist.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: on,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FxIconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(dialogCtx),
                        icon: Icon(Icons.close_rounded, color: muted),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.cardBorder(context)),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH - 92),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (playlist.id != 'recent')
                          action(
                            icon: Icons.edit_outlined,
                            label: S.of(context).editPlaylist,
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _showEditDialog(context, ref, playlist);
                            },
                          ),
                        if (playlist.id != 'favorites' &&
                            playlist.songCount > 0)
                          action(
                            icon: Icons.favorite_border_rounded,
                            label: S.of(context).addAllToFavorites,
                            onTap: () async {
                              final int added;
                              try {
                                added = await ref
                                    .read(playlistServiceProvider)
                                    .addAllSongsToFavorites(playlist.id);
                              } catch (error) {
                                if (!context.mounted) return;
                                showAppNotification(
                                  '${S.of(context).addFailed}: $error',
                                  type: AppNotificationType.error,
                                );
                                return;
                              }
                              if (!dialogCtx.mounted) return;
                              Navigator.pop(dialogCtx);
                              if (!context.mounted) return;
                              showAppNotification(
                                added == 0
                                    ? S.of(context).alreadyInFavorites
                                    : S.of(context).addedToFavorites(added),
                                type: added == 0
                                    ? AppNotificationType.info
                                    : AppNotificationType.success,
                              );
                            },
                          ),
                        if (playlist.id != 'favorites' &&
                            playlist.id != 'recent')
                          action(
                            icon: Icons.delete_outline_rounded,
                            label: S.of(context).deletePlaylist,
                            destructive: true,
                            onTap: () async {
                              try {
                                await ref
                                    .read(playlistServiceProvider)
                                    .deletePlaylist(playlist.id);
                              } catch (error) {
                                if (!context.mounted) return;
                                showAppNotification(
                                  '${S.of(context).deleteFailed}: $error',
                                  type: AppNotificationType.error,
                                );
                                return;
                              }
                              if (!dialogCtx.mounted) return;
                              Navigator.pop(dialogCtx);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 预设歌单入口卡。
///
/// 五个入口共用同一套玻璃材质，只有图标色调区分。之前的做法是每张卡都
/// 自带一条高饱和渐变（绿 / 橙 / 紫 / 品红 / 蓝），堆在一起就是一块调色板，
/// 与首页快捷卡的材质也对不上。统一材质后，页面靠图标色分门别类，
/// 主次交给字号和位置，而不是靠谁更亮。
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onPlay,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// 为 null 时按钮仍在位（禁用态），避免卡片右侧塌成一块空白。
  final VoidCallback? onPlay;

  static const double _height = 72;
  static const double _iconExtent = 52;

  /// 图标在卡内垂直居中，上下留白必然等于 (_height - _iconExtent) / 2 = 10。
  /// 原来图标只有 38，四边各空 17，一行看下来像五条空盒子；图标放大到 52
  /// 后留白减半，左右仍用同一个 10，四边才对得上。
  static const double _inset = (_height - _iconExtent) / 2;

  @override
  Widget build(BuildContext context) {
    return HoverFloat(
      child: Pressable(
        borderRadius: BorderRadius.circular(18),
        captureExpandRect: true,
        onTap: onTap,
        // 固定高度：五个入口的副标题长短不一（"3 songs" / "Choose a folder
        // to scan this device"），高度随内容走会让并排两张卡的基线错开。
        child: SizedBox(
          height: _height,
          child: OrigoChromeSurface(
            borderRadius: BorderRadius.circular(18),
            accent: tone,
            // 四边同一个 10：内容区 52 正好等于图标，图标即卡的内边界。
            padding: const EdgeInsets.all(_inset),
            child: Row(
              children: [
                Container(
                  width: _iconExtent,
                  height: _iconExtent,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(_iconExtent * 0.29),
                  ),
                  child: Icon(icon, color: tone, size: _iconExtent * 0.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.onScaffold(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2.5),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.secondaryText(context),
                          fontSize: 11.8,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // 中性色而不是 accent：五张卡各带一个 accent 圆点会在右列排成
                // 五颗同色的亮点，视线先落在按钮上而不是歌单名。左侧图标已经
                // 承担了分类的颜色信息，这里只需要一个安静的播放 affordance。
                CardPlayButton(
                  // 38 而不是 34：卡片高 72、内容 52，34 的按钮夹在中间
                  // 明显偏小，和左边的 52 图标不成比例。
                  size: 38,
                  color: AppColors.onScaffold(context),
                  backgroundColor: AppColors.isDark(context)
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.black.withValues(alpha: 0.05),
                  onPressed: onPlay,
                  icon: Icon(
                    Icons.play_arrow_rounded,
                    color: onPlay == null
                        ? AppColors.mutedText(context)
                        : AppColors.onScaffold(context).withValues(alpha: 0.72),
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 歌单页列表项的轻量描述（不包含真实 widget，避免屏幕外内容被构建）。
sealed class _PlaylistBodyItem {
  const _PlaylistBodyItem();
}

class _BodyPresetGrid extends _PlaylistBodyItem {
  const _BodyPresetGrid();
}

class _BodyGap extends _PlaylistBodyItem {
  const _BodyGap(this.height);

  final double height;
}

class _BodyHeader extends _PlaylistBodyItem {
  const _BodyHeader({required this.title, required this.trailing});

  final String title;
  final bool trailing;
}

class _BodyPlaylistItem extends _PlaylistBodyItem {
  const _BodyPlaylistItem(this.playlist);

  final Playlist playlist;
}

class _BodySongHitItem extends _PlaylistBodyItem {
  const _BodySongHitItem(this.hit);

  final PlaylistSongMatch hit;
}

class _BodySongHitPair extends _PlaylistBodyItem {
  const _BodySongHitPair(this.first, this.second);

  final PlaylistSongMatch first;
  final PlaylistSongMatch? second;
}

class _BodyLoading extends _PlaylistBodyItem {
  const _BodyLoading();
}

class _BodyEmptyResult extends _PlaylistBodyItem {
  const _BodyEmptyResult();
}
