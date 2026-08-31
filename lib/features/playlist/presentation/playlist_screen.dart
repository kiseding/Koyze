import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../../../core/widgets/card_play_button.dart';
import '../domain/playlist.dart';
import '../domain/playlist_import_service.dart';
import '../domain/playlist_service.dart';
import '../../player/domain/music_item.dart';
import 'playlist_provider.dart';
import '../../player/presentation/player_provider.dart';
import '../../recommend/presentation/recommendation_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/koyze_sheet.dart';

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

    final scheme = Theme.of(context).colorScheme;
    final bodyItems = _bodyItems(
      songHits: songHits,
      filteredPlaylists: filteredPlaylists,
      isLoading: songSearch?.isLoading ?? false,
    );
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 主壳已固定预留底部导航和迷你播放器；键盘直接覆盖它们，避免重复预留空白。
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.music_note, color: scheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                '我的歌单',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          actions: [
            FxIconButton(
              tooltip: '导入歌单',
              icon: Icon(
                Icons.playlist_add,
                color: AppColors.onScaffold(context),
                size: 24,
              ),
              onPressed: () => _showImportDialog(context, ref),
            ),
            FxIconButton(
              tooltip: '新建歌单',
              icon: Icon(
                Icons.add,
                color: AppColors.onScaffold(context),
                size: 24,
              ),
              onPressed: () => _showCreateDialog(context, ref),
            ),
          ],
        ),
        // 搜索框固定在列表外，避免 ListView 子项重建导致输入法收起
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                  hintText: '在库中搜索歌曲/歌单',
                  hintStyle: TextStyle(
                    color: AppColors.mutedText(context),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppColors.mutedText(context),
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : FxIconButton(
                          tooltip: '清除搜索内容',
                          icon: Icon(
                            Icons.clear,
                            size: 18,
                            color: AppColors.mutedText(context),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  fillColor: AppColors.miniBar(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
      showAppNotification('加载歌曲失败: $error', type: AppNotificationType.error);
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
        const _BodyFavoritesCard(),
        const _BodyGap(12),
        const _BodyRecommendCard(),
        const _BodyGap(12),
        const _BodyLocalCard(),
        const _BodyGap(12),
        const _BodyRecentCard(),
        const _BodyGap(24),
        const _BodyHeader(title: '自定义歌单', trailing: true),
        const _BodyGap(12),
        for (final playlist in filteredPlaylists) _BodyPlaylistItem(playlist),
      ];
    }
    final items = <_PlaylistBodyItem>[
      if (isLoading) const _BodyLoading(),
      if (songHits.isNotEmpty) ...[
        _BodyHeader(title: '歌曲 (${songHits.length})', trailing: false),
        const _BodyGap(8),
        for (final hit in songHits) _BodySongHitItem(hit),
        const _BodyGap(16),
      ],
      if (filteredPlaylists.isNotEmpty) ...[
        _BodyHeader(title: '歌单 (${filteredPlaylists.length})', trailing: false),
        const _BodyGap(8),
        for (final playlist in filteredPlaylists) _BodyPlaylistItem(playlist),
      ],
      if (songHits.isEmpty && filteredPlaylists.isEmpty)
        const _BodyEmptyResult(),
    ];
    return items;
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
      _BodyFavoritesCard() => _buildFavoritesCard(
        context,
        ref,
        favorites,
        playerService,
      ),
      _BodyRecommendCard() => _buildRecommendCard(context, ref, playerService),
      _BodyLocalCard() => _buildLocalCard(context, ref, local, playerService),
      _BodyRecentCard() => _buildRecentCard(
        context,
        ref,
        recent,
        playerService,
      ),
      _BodyGap(:final height) => SizedBox(height: height),
      _BodyHeader(:final title, :final trailing) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          if (trailing)
            FxIconButton(
              tooltip: '排序歌单',
              icon: Icon(
                Icons.sort,
                color: scheme.onSurface.withAlpha(120),
                size: 20,
              ),
              onPressed: () => _showSortMenu(context),
            ),
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
      _BodyLoading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      _BodyEmptyResult() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            '未找到匹配的歌曲或歌单',
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(context)),
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
          style: TextStyle(color: AppColors.onScaffold(context), fontSize: 14),
        ),
        subtitle: Text(
          '${song.singer} · ${playlist.name}',
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
    );
  }

  Widget _buildFavoritesCard(
    BuildContext context,
    WidgetRef ref,
    Playlist? favorites,
    dynamic playerService,
  ) {
    final songCount = favorites?.songCount ?? 0;
    final accent = AppColors.accentOf(context);
    // 主题的 onPrimary 在深色下是黑色（黄底黑字），但渐变卡片视觉上应统一为白字。
    const onAccent = Colors.white;

    return HoverFloat(
      child: Pressable(
        borderRadius: BorderRadius.circular(16),
        captureExpandRect: true,
        onTap: () {
          context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'favorites'},
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withAlpha(220), accent.withAlpha(120)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: onAccent.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
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
                    const Text(
                      '收藏列表',
                      style: TextStyle(
                        color: onAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$songCount 首歌曲',
                      style: TextStyle(
                        color: onAccent.withAlpha(200),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              CardPlayButton(
                color: onAccent,
                backgroundColor: onAccent.withAlpha(40),
                onPressed: favorites != null && favorites.songCount > 0
                    ? () => _playPlaylist(playerService, favorites)
                    : null,
                icon: const Icon(
                  Icons.play_arrow_rounded,
                  color: onAccent,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalCard(
    BuildContext context,
    WidgetRef ref,
    Playlist? local,
    dynamic playerService,
  ) {
    final songCount = local?.songCount ?? 0;
    // 紫色渐变（与收藏 / 最近播放卡片结构一致）
    const purple = Colors.purple;
    const onPurple = Colors.white;

    return HoverFloat(
      child: Pressable(
        borderRadius: BorderRadius.circular(16),
        captureExpandRect: true,
        onTap: () {
          context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'local'},
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [purple.withAlpha(220), purple.withAlpha(120)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: onPurple.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.library_music,
                  color: onPurple,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '本地音乐',
                      style: TextStyle(
                        color: onPurple,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      songCount == 0 ? '选择文件夹扫描设备歌曲' : '$songCount 首歌曲',
                      style: TextStyle(
                        color: onPurple.withAlpha(200),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              CardPlayButton(
                color: onPurple,
                backgroundColor: onPurple.withAlpha(40),
                onPressed: local != null && local.songCount > 0
                    ? () => _playPlaylist(playerService, local)
                    : null,
                icon: const Icon(
                  Icons.play_arrow_rounded,
                  color: onPurple,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentCard(
    BuildContext context,
    WidgetRef ref,
    Playlist? recent,
    dynamic playerService,
  ) {
    final songCount = recent?.songCount ?? 0;
    // 蓝色渐变（与收藏列表结构一致，仅替换为蓝色）
    const blue = Colors.blue;
    final onBlue = Colors.white;

    return HoverFloat(
      child: Pressable(
        borderRadius: BorderRadius.circular(16),
        captureExpandRect: true,
        onTap: () {
          context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'recent'},
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [blue.withAlpha(220), blue.withAlpha(120)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: onBlue.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.history_rounded, color: onBlue, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '最近播放',
                      style: TextStyle(
                        color: onBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$songCount 首歌曲',
                      style: TextStyle(
                        color: onBlue.withAlpha(200),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              CardPlayButton(
                color: onBlue,
                backgroundColor: onBlue.withAlpha(40),
                onPressed: recent != null && recent.songCount > 0
                    ? () => _playPlaylist(playerService, recent)
                    : null,
                icon: Icon(Icons.play_arrow_rounded, color: onBlue, size: 30),
              ),
            ],
          ),
        ),
      ),
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
    const orange = Color(0xFFFF8F1F);
    const onOrange = Colors.white;

    return HoverFloat(
      child: Pressable(
        borderRadius: BorderRadius.circular(16),
        captureExpandRect: true,
        onTap: () {
          context.push('/recommend');
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [orange.withAlpha(235), orange.withAlpha(130)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: onOrange.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: onOrange,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '猜你喜欢',
                      style: TextStyle(
                        color: onOrange,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count > 0 ? '为你推荐 $count 首歌曲' : '收藏歌曲后为你推荐',
                      style: TextStyle(
                        color: onOrange.withAlpha(200),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              CardPlayButton(
                color: onOrange,
                backgroundColor: onOrange.withAlpha(40),
                onPressed: recommendations.isEmpty
                    ? null
                    : () => playerService.playPlaylist(
                        recommendations.map((item) => item.song).toList(),
                        manualPlayName: recommendations.first.song.name,
                      ),
                icon: const Icon(
                  Icons.play_arrow_rounded,
                  color: onOrange,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Pressable(
        borderRadius: BorderRadius.circular(12),
        captureExpandRect: true,
        onTap: () {
          _openPlaylist(context, playlist);
        },
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
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
                    fontSize: 24,
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
                    playlist.name,
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlist.songCount} 首歌曲 · ${playlist.description ?? "私人"}',
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
            FxIconButton(
              icon: Icon(
                Icons.more_vert,
                color: AppColors.mutedText(context),
                size: 20,
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

    showDialog(
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
        return AlertDialog(
          backgroundColor: AppColors.dialogBg(dialogContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '创建歌单',
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
                  hintText: '歌单名称',
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
                  hintText: '描述（可选）',
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
                '取消',
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
                      '创建失败: $error',
                      type: AppNotificationType.error,
                    );
                  }
                }
              },
              child: Text(
                '创建',
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

    showDialog(
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
        return AlertDialog(
          backgroundColor: AppColors.dialogBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '编辑歌单',
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
                  hintText: '歌单名称',
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
                  hintText: '描述（可选）',
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
                '取消',
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
                      '保存失败: $error',
                      type: AppNotificationType.error,
                    );
                  }
                }
              },
              child: Text(
                '保存',
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
      backgroundColor: AppColors.dialogBg(context),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.mutedText(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '排序方式',
                style: TextStyle(
                  color: AppColors.onScaffold(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _sortOption(
              context,
              PlaylistSortMode.recent,
              Icons.access_time,
              '最近添加',
            ),
            _sortOption(
              context,
              PlaylistSortMode.name,
              Icons.sort_by_alpha,
              '名称排序',
            ),
            _sortOption(
              context,
              PlaylistSortMode.songCount,
              Icons.music_note,
              '歌曲数量',
            ),
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
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected
            ? AppColors.accentOf(context)
            : AppColors.onScaffold(context),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? AppColors.accentOf(context)
              : AppColors.onScaffold(context),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: AppColors.accentOf(context), size: 20)
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

    await showDialog(
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
            return AlertDialog(
              backgroundColor: AppColors.dialogBg(context),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
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
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '导入歌单',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '粘贴分享链接或输入歌单 ID',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          FxIconButton(
                            tooltip: '关闭导入歌单',
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
                              '来源平台',
                              style: TextStyle(
                                color: AppColors.secondaryText(ctx),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'tx',
                                  label: Text('QQ'),
                                  icon: Icon(Icons.music_note_rounded),
                                ),
                                ButtonSegment(
                                  value: 'kw',
                                  label: Text('酷我'),
                                  icon: Icon(Icons.graphic_eq_rounded),
                                ),
                                ButtonSegment(
                                  value: 'wy',
                                  label: Text('网易'),
                                  icon: Icon(Icons.album_rounded),
                                ),
                              ],
                              selected: {platform},
                              onSelectionChanged: busy
                                  ? null
                                  : (value) =>
                                        setLocal(() => platform = value.first),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              '歌单链接或 ID',
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
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.done,
                              autocorrect: false,
                              enabled: !busy,
                              minLines: 2,
                              maxLines: 3,
                              style: TextStyle(
                                color: AppColors.onScaffold(ctx),
                              ),
                              decoration: const InputDecoration(
                                hintText:
                                    '例如：https://y.qq.com/n/ryqq/playlist/123\n或直接输入数字 ID',
                                alignLabelWithHint: true,
                                prefixIcon: Icon(Icons.link_rounded),
                              ).applyDefaults(Theme.of(ctx).inputDecorationTheme),
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
                                  setLocal(() => error = '请输入链接或 ID');
                                  return;
                                }
                                setLocal(() {
                                  busy = true;
                                  error = null;
                                });
                                try {
                                  final imported = await PlaylistImportService()
                                      .import(
                                        input: input,
                                        platformHint: platform,
                                      );
                                  if (!ctx.mounted) return;
                                  final ok = await showDialog<bool>(
                                    context: ctx,
                                    builder: (c2) => AlertDialog(
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
                                        '共 ${imported.songs.length} 首，确认导入到本地歌单？',
                                        style: TextStyle(
                                          color: AppColors.mutedText(context),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c2, false),
                                          child: Text(
                                            '取消',
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
                                            '导入',
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
                                          description: '导入自${imported.source}',
                                          songs: imported.songs,
                                        );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (context.mounted) {
                                      showAppNotification(
                                        '已导入「${imported.name}」${imported.songs.length} 首',
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: Text(busy ? '正在解析歌单…' : '解析歌单'),
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
    final maxW = media.size.width.clamp(280.0, 420.0);

    showDialog<void>(
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

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
            child: Material(
              color: AppColors.dialogBg(context),
              elevation: 8,
              shadowColor: Colors.black38,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            playlist.name,
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
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (playlist.id != 'recent')
                            action(
                              icon: Icons.edit_outlined,
                              label: '编辑歌单',
                              onTap: () {
                                Navigator.pop(dialogCtx);
                                _showEditDialog(context, ref, playlist);
                              },
                            ),
                          if (playlist.id != 'favorites' &&
                              playlist.songCount > 0)
                            action(
                              icon: Icons.favorite_border_rounded,
                              label: '全部添加到收藏列表',
                              onTap: () async {
                                final int added;
                                try {
                                  added = await ref
                                      .read(playlistServiceProvider)
                                      .addAllSongsToFavorites(playlist.id);
                                } catch (error) {
                                  if (!context.mounted) return;
                                  showAppNotification(
                                    '添加失败: $error',
                                    type: AppNotificationType.error,
                                  );
                                  return;
                                }
                                if (!dialogCtx.mounted) return;
                                Navigator.pop(dialogCtx);
                                if (!context.mounted) return;
                                showAppNotification(
                                  added == 0
                                      ? '所有歌曲已在收藏列表中'
                                      : '已添加 $added 首到收藏列表',
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
                              label: '删除歌单',
                              destructive: true,
                              onTap: () async {
                                try {
                                  await ref
                                      .read(playlistServiceProvider)
                                      .deletePlaylist(playlist.id);
                                } catch (error) {
                                  if (!context.mounted) return;
                                  showAppNotification(
                                    '删除失败: $error',
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
          ),
        );
      },
    );
  }
}

/// 歌单页列表项的轻量描述（不包含真实 widget，避免屏幕外内容被构建）。
sealed class _PlaylistBodyItem {
  const _PlaylistBodyItem();
}

class _BodyFavoritesCard extends _PlaylistBodyItem {
  const _BodyFavoritesCard();
}

class _BodyRecommendCard extends _PlaylistBodyItem {
  const _BodyRecommendCard();
}

class _BodyLocalCard extends _PlaylistBodyItem {
  const _BodyLocalCard();
}

class _BodyRecentCard extends _PlaylistBodyItem {
  const _BodyRecentCard();
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

class _BodyLoading extends _PlaylistBodyItem {
  const _BodyLoading();
}

class _BodyEmptyResult extends _PlaylistBodyItem {
  const _BodyEmptyResult();
}
