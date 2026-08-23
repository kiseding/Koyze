import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/pagination/page_range.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/page_navigation_bar.dart';
import '../domain/playlist.dart';
import 'playlist_occurrence.dart';
import 'playlist_provider.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    this.focusSongId,
  });

  final String playlistId;
  final String? focusSongId;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  bool _isEditing = false;
  final List<PlaylistSongOccurrence> _reorderedSongs = [];
  String? _reorderedPlaylistId;
  final ScrollController _scrollController = ScrollController();
  bool _initialFocusStarted = false;
  int? _pendingCenteredSongIndex;
  int _pageIndex = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Playlist? _resolvePlaylist() {
    ref.watch(playlistRevisionProvider);
    return ref.watch(playlistServiceProvider).getPlaylist(widget.playlistId);
  }

  void _syncReorderedSongs(Playlist playlist, {bool force = false}) {
    if (!force &&
        _isEditing &&
        _reorderedPlaylistId == playlist.id &&
        _reorderedSongs.isNotEmpty) {
      return;
    }
    _reorderedPlaylistId = playlist.id;
    _reorderedSongs
      ..clear()
      ..addAll(buildPlaylistOccurrences(playlist.id, playlist.songs));
  }

  void _prepareInitialFocus(Playlist playlist, dynamic playerService) {
    if (_initialFocusStarted) return;
    _initialFocusStarted = true;

    final focusId = widget.focusSongId;
    if (focusId != null) {
      final index = playlist.songs.indexWhere((song) => song.id == focusId);
      if (index >= 0) {
        _setInitialFocusIndex(index);
      } else if (playlist.songCount > 0) {
        _loadFocusPage(playlist, focusId);
      }
      return;
    }

    if (playerService.currentLazyPlaylistId != playlist.id) return;
    final index = playerService.mediaItem?.extras?['_lazyPlaylistIndex'];
    if (index is int && index >= 0 && index < playlist.songCount) {
      _setInitialFocusIndex(index);
    }
  }

  void _setInitialFocusIndex(int index) {
    _pageIndex = PageRange.pageForItem(index: index);
    _pendingCenteredSongIndex = index;
  }

  Future<void> _loadFocusPage(Playlist playlist, String focusId) async {
    try {
      final songs = await ref
          .read(playlistServiceProvider)
          .getAllSongs(playlist.id);
      final index = songs.indexWhere((song) => song.id == focusId);
      if (!mounted || index < 0) return;
      setState(() => _setInitialFocusIndex(index));
    } catch (error) {
      if (mounted) _showMutationError('定位歌曲失败', error);
    }
  }

  void _centerInitialSong(PageRange range) {
    final index = _pendingCenteredSongIndex;
    if (index == null ||
        PageRange.pageForItem(index: index) != range.pageIndex) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      const itemExtent = 72.0;
      final position = _scrollController.position;
      final itemTop = (index % PageRange.defaultPageSize) * itemExtent;
      final offset = (itemTop - (position.viewportDimension - itemExtent) / 2)
          .clamp(0.0, position.maxScrollExtent);
      _scrollController.jumpTo(offset);
      _pendingCenteredSongIndex = null;
    });
  }

  PageRange _pageRangeFor(int itemCount) {
    return PageRange(itemCount: itemCount, pageIndex: _pageIndex);
  }

  void _setPage(int pageIndex, int itemCount) {
    setState(() {
      _pendingCenteredSongIndex = null;
      _pageIndex = PageRange(
        itemCount: itemCount,
        pageIndex: pageIndex,
      ).pageIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  Widget _buildPageNavigation(PageRange range) {
    return PageNavigationBar(
      pageIndex: range.pageIndex,
      pageCount: range.pageCount,
      onPageChanged: (pageIndex) => _setPage(pageIndex, range.itemCount),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _resolvePlaylist();
    final playerService = ref.watch(playerServiceProvider);
    final focusId = widget.focusSongId;

    if (playlist == null) {
      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            title: Text(
              '歌单',
              style: TextStyle(color: AppColors.onScaffold(context)),
            ),
          ),
          body: Center(
            child: Text(
              '歌单不存在',
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
        ),
      );
    }

    if (_reorderedPlaylistId != playlist.id) {
      _syncReorderedSongs(playlist, force: true);
    }
    _prepareInitialFocus(playlist, playerService);
    final range = _pageRangeFor(playlist.songCount);
    final songsPage = !_isEditing && playlist.songCount > 0
        ? ref.watch(
            playlistSongsPageProvider(
              PlaylistSongsPageRequest(
                playlistId: playlist.id,
                pageIndex: range.pageIndex,
              ),
            ),
          )
        : null;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 列表可滚动到栏内部（栏高度不变），顶栏渐变才有可见过渡。
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          // 顶栏背景在栏内部渐变：顶部实色 → 底部 100% 透明。
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          leading: FxIconButton(
            tooltip: _isEditing ? '取消编辑' : '返回',
            icon: AnimatedIconSwitch(
              icon: _isEditing ? Icons.close : Icons.arrow_back,
              keyValue: _isEditing ? Icons.close : Icons.arrow_back,
              color: AppColors.onScaffold(context),
            ),
            onPressed: () {
              if (_isEditing) {
                setState(() {
                  _isEditing = false;
                  _syncReorderedSongs(playlist, force: true);
                });
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            _isEditing ? '编辑歌单' : '${playlist.name}（${playlist.songCount}首）',
            style: TextStyle(
              color: AppColors.onScaffold(context),
              fontSize: 18,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (!_isEditing && playlist.songCount > 0)
              FxIconButton(
                tooltip: '播放全部',
                onPressed: () => _playSong(playerService, playlist, 0),
                icon: Icon(
                  Icons.play_circle_fill,
                  color: AppColors.accentOf(context),
                  size: 28,
                ),
              ),
            if (_isEditing)
              TextButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(playlistServiceProvider)
                        .updatePlaylist(
                          id: playlist.id,
                          songs: _reorderedSongs
                              .map((entry) => entry.song)
                              .toList(),
                        );
                    if (mounted) setState(() => _isEditing = false);
                  } catch (error) {
                    _showMutationError('保存失败', error);
                  }
                },
                child: Text(
                  '保存',
                  style: TextStyle(color: AppColors.accentOf(context)),
                ),
              )
            else
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: AppColors.onScaffold(context),
                ),
                color: AppColors.dialogBg(context),
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                offset: const Offset(0, 8),
                popUpAnimationStyle: const AnimationStyle(
                  duration: Duration(milliseconds: 280),
                  reverseDuration: Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
                onSelected: (value) async {
                  try {
                    switch (value) {
                      case 'play_all':
                        if (playlist.songCount > 0) {
                          await _playSong(playerService, playlist, 0);
                        }
                      case 'favorite_all':
                        final added = await ref
                            .read(playlistServiceProvider)
                            .addAllSongsToFavorites(playlist.id);
                        if (mounted) {
                          showAppNotification(
                            added > 0 ? '已收藏 $added 首歌曲' : '歌曲已在收藏中',
                            type: AppNotificationType.success,
                          );
                        }
                      case 'clear_favorites':
                        await _showClearFavoritesDialog(context, ref, playlist);
                      case 'edit':
                        _showEditDialog(context, ref, playlist);
                      case 'sort_name':
                        await ref
                            .read(playlistServiceProvider)
                            .sortSongsByName(playlist.id);
                        if (!mounted) return;
                        setState(() {
                          final latest = ref
                              .read(playlistServiceProvider)
                              .getPlaylist(playlist.id);
                          if (latest != null) {
                            _syncReorderedSongs(latest, force: true);
                          }
                        });
                      case 'sort_artist':
                        await ref
                            .read(playlistServiceProvider)
                            .sortSongsByArtist(playlist.id);
                        if (!mounted) return;
                        setState(() {
                          final latest = ref
                              .read(playlistServiceProvider)
                              .getPlaylist(playlist.id);
                          if (latest != null) {
                            _syncReorderedSongs(latest, force: true);
                          }
                        });
                      case 'sort_duration':
                        await ref
                            .read(playlistServiceProvider)
                            .sortSongsByDuration(playlist.id);
                        if (!mounted) return;
                        setState(() {
                          final latest = ref
                              .read(playlistServiceProvider)
                              .getPlaylist(playlist.id);
                          if (latest != null) {
                            _syncReorderedSongs(latest, force: true);
                          }
                        });
                      case 'reorder':
                        final songs = await ref
                            .read(playlistServiceProvider)
                            .getAllSongs(playlist.id);
                        if (!mounted) return;
                        setState(() {
                          _isEditing = true;
                          _syncReorderedSongs(
                            playlist.copyWith(songs: songs),
                            force: true,
                          );
                        });
                      case 'delete':
                        _showDeleteDialog(context, ref, playlist);
                    }
                  } catch (error) {
                    _showMutationError('操作失败', error);
                  }
                },
                itemBuilder: (context) {
                  final on = AppColors.onScaffold(context);
                  return [
                    PopupMenuItem(
                      value: 'play_all',
                      child: Text('播放全部', style: TextStyle(color: on)),
                    ),
                    if (playlist.id == 'local')
                      PopupMenuItem(
                        value: 'favorite_all',
                        child: Text('收藏所有', style: TextStyle(color: on)),
                      ),
                    if (playlist.id == 'favorites' && playlist.songCount > 0)
                      const PopupMenuItem(
                        value: 'clear_favorites',
                        child: Text(
                          '一键取消收藏',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    if (playlist.id != 'recent')
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('编辑信息', style: TextStyle(color: on)),
                      ),
                    PopupMenuItem(
                      value: 'reorder',
                      child: Text('手动排序', style: TextStyle(color: on)),
                    ),
                    PopupMenuItem(
                      value: 'sort_name',
                      child: Text('按歌名排序', style: TextStyle(color: on)),
                    ),
                    PopupMenuItem(
                      value: 'sort_artist',
                      child: Text('按歌手排序', style: TextStyle(color: on)),
                    ),
                    PopupMenuItem(
                      value: 'sort_duration',
                      child: Text('按时长排序', style: TextStyle(color: on)),
                    ),
                    if (playlist.id != 'favorites' &&
                        playlist.id != 'recent' &&
                        playlist.id != 'local')
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('删除歌单', style: TextStyle(color: on)),
                      ),
                  ];
                },
              ),
          ],
        ),
        body: playlist.songCount == 0
            ? Center(
                child: Text(
                  '暂无歌曲',
                  style: TextStyle(color: AppColors.mutedText(context)),
                ),
              )
            : _isEditing
            ? _buildEditableList(playlist)
            : songsPage!.when(
                skipLoadingOnRefresh: true,
                data: (page) => _buildNormalList(
                  playerService,
                  playlist,
                  page.songs,
                  range,
                  focusId,
                ),
                loading: () => _buildPageLoading(range),
                error: (error, _) => Center(child: Text('加载歌曲失败: $error')),
              ),
      ),
    );
  }

  Widget _buildEditableList(Playlist playlist) {
    final range = _pageRangeFor(_reorderedSongs.length);
    final songs = pageSlice(_reorderedSongs, range);
    // 列表可滚动到栏内部；顶部/底部预留栏空间，避免内容被栏遮挡。
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: ReorderableListView.builder(
            itemCount: songs.length,
            padding: EdgeInsets.only(
              top: topInset,
              // 页码栏是悬浮控件，列表继续延伸到屏幕底部；
              // 不再按页码栏整块高度扣除，避免胶囊下方出现空白。
              bottom:
                  bottomInset +
                  (range.pageCount > 1
                      ? PageNavigationBar.listBottomPadding
                      : 0),
            ),
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final item = _reorderedSongs.removeAt(range.start + oldIndex);
                _reorderedSongs.insert(range.start + newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final entry = songs[index];
              final song = entry.song;
              return ListTile(
                key: ValueKey(entry.key),
                leading: Icon(
                  Icons.drag_handle,
                  color: AppColors.mutedText(context),
                ),
                title: Text(
                  song.name,
                  style: TextStyle(color: AppColors.onScaffold(context)),
                ),
                subtitle: Text(
                  song.singer,
                  style: TextStyle(
                    color: AppColors.mutedText(context),
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildPageNavigation(range),
        ),
      ],
    );
  }

  Widget _buildNormalList(
    dynamic playerService,
    Playlist playlist,
    List<MusicItem> songs,
    PageRange range,
    String? focusId,
  ) {
    _centerInitialSong(range);
    // 页面级一次性读取收藏集合，行内直接查 Set，避免滚动时每行创建异步查询。
    final favoriteIds =
        ref.watch(favoriteIdsProvider).valueOrNull ?? const <String>{};
    // 列表全屏可滚动到栏内部；顶部/底部预留栏空间，滚动时才进入渐变区。
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: ListView.builder(
            controller: _scrollController,
            itemExtent: 72,
            itemCount: songs.length,
            padding: EdgeInsets.only(
              top: topInset,
              // 页码栏是悬浮控件，列表继续延伸到屏幕底部。
              bottom:
                  bottomInset +
                  (range.pageCount > 1
                      ? PageNavigationBar.listBottomPadding
                      : 0),
            ),
            itemBuilder: (context, index) {
              final song = songs[index];
              final songIndex = range.start + index;
              final focused = focusId != null && song.id == focusId;
              return Container(
                color: focused
                    ? AppColors.accentOf(context).withAlpha(28)
                    : null,
                child: ListTile(
                  onTap: () => _playSong(playerService, playlist, songIndex),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: song.artwork != null && song.artwork!.isNotEmpty
                          ? ArtworkImage(
                              song.artwork!,
                              fit: BoxFit.cover,
                              cacheWidth: 96,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.music_note,
                                color: AppColors.mutedText(context),
                              ),
                            )
                          : Icon(
                              Icons.music_note,
                              color: AppColors.mutedText(context),
                            ),
                    ),
                  ),
                  title: Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    song.singer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 12,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 收藏按钮与更多按钮分开，留出呼吸感避免误触。
                      FavoriteButton(
                        song: song,
                        isFavorite: favoriteIds.contains(song.identityKey),
                      ),
                      FxIconButton(
                        tooltip: '更多操作',
                        icon: Icon(
                          Icons.more_vert,
                          color: AppColors.mutedText(context),
                          size: 20,
                        ),
                        onPressed: () {
                          showKoyzeSheet(
                            context: context,
                            backgroundColor: AppColors.dialogBg(context),
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.play_arrow),
                                    title: const Text('播放'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _playSong(
                                        playerService,
                                        playlist,
                                        songIndex,
                                      );
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.delete_outline),
                                    title: const Text('从歌单移除'),
                                    onTap: () async {
                                      try {
                                        await ref
                                            .read(playlistServiceProvider)
                                            .removeSongOccurrence(
                                              playlist.id,
                                              songIndex,
                                            );
                                      } catch (error) {
                                        if (mounted) {
                                          _showMutationError('移除失败', error);
                                        }
                                        return;
                                      }
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // 底栏悬浮在列表之上（栏高度不变），列表可滚动到栏内部。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildPageNavigation(range),
        ),
      ],
    );
  }

  Widget _buildPageLoading(PageRange range) {
    return Stack(
      children: [
        const Positioned.fill(child: SizedBox.shrink()),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildPageNavigation(range),
        ),
      ],
    );
  }

  Future<void> _playSong(
    dynamic playerService,
    Playlist playlist,
    int index,
  ) async {
    try {
      if (playlist.songCount <= 0) return;
      await playerService.playPagedPlaylist(
        songCount: playlist.songCount,
        startIndex: index,
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
      _showMutationError('加载歌曲失败', error);
    }
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
                ),
              ),
              TextField(
                controller: descController,
                focusNode: descFocus,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: AppColors.onScaffold(ctx)),
                decoration: InputDecoration(
                  hintText: '描述',
                  hintStyle: TextStyle(color: AppColors.mutedText(ctx)),
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
                try {
                  await ref
                      .read(playlistServiceProvider)
                      .updatePlaylist(
                        id: playlist.id,
                        name: nameController.text,
                        description: descController.text,
                      );
                } catch (error) {
                  if (mounted) _showMutationError('保存失败', error);
                  return;
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
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

  Future<void> _showClearFavoritesDialog(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dialogBg(context),
        title: Text(
          '取消全部收藏？',
          style: TextStyle(color: AppColors.onScaffold(context)),
        ),
        content: Text(
          '将从收藏列表移除 ${playlist.songCount} 首歌曲，此操作不会删除歌单中的原歌曲。',
          style: TextStyle(color: AppColors.secondaryText(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '全部取消收藏',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final playlistService = ref.read(playlistServiceProvider);
      final songs = await playlistService.getAllSongs('favorites');
      final removed = await playlistService.removeSongsFromPlaylist(
        'favorites',
        songs.map((song) => song.identityKey),
      );
      if (!mounted) return;
      setState(() {
        _pageIndex = 0;
        _pendingCenteredSongIndex = null;
        _syncReorderedSongs(
          playlist.copyWith(songs: const <MusicItem>[]),
          force: true,
        );
      });
      showAppNotification(
        removed > 0 ? '已取消收藏 $removed 首歌曲' : '收藏列表已为空',
        type: AppNotificationType.success,
      );
    } catch (error) {
      _showMutationError('取消收藏失败', error);
    }
  }

  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dialogBg(context),
        title: Text(
          '删除歌单',
          style: TextStyle(color: AppColors.onScaffold(context)),
        ),
        content: Text(
          '确定删除「${playlist.name}」？',
          style: TextStyle(color: AppColors.secondaryText(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ref
                    .read(playlistServiceProvider)
                    .deletePlaylist(playlist.id);
              } catch (error) {
                if (mounted) _showMutationError('删除失败', error);
                return;
              }
              if (!ctx.mounted || !context.mounted) return;
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showMutationError(String action, Object error) {
    if (!mounted) return;
    showAppNotification('$action: $error', type: AppNotificationType.error);
  }
}
