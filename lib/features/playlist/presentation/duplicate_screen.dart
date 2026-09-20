import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/animations/micro_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../domain/duplicate_detector.dart';
import '../domain/playlist.dart';
import 'playlist_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';

class DuplicateScreen extends ConsumerStatefulWidget {
  const DuplicateScreen({super.key});

  @override
  ConsumerState<DuplicateScreen> createState() => _DuplicateScreenState();
}

class _DuplicateScreenState extends ConsumerState<DuplicateScreen> {
  bool _removing = false;

  /// `null` 表示还没用手动改过，沿用每组「推荐保留以外」的默认勾选。
  Set<String>? _userSelection;

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(hydratedPlaylistsProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 列表可滚动到栏内部（栏高度不变），顶栏磨砂才可见。
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          leading: FxIconButton(
            tooltip: '返回',
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            '重复歌曲',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onScaffold(context),
            ),
          ),
          actions: [
            if (playlistsAsync.valueOrNull != null)
              ..._appBarActions(_detectGroups(playlistsAsync.requireValue)),
          ],
        ),
        body: SafeArea(
          top: false,
          child: playlistsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('加载失败')),
            data: (playlists) {
              final groups = _detectGroups(playlists);
              if (groups.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.task_alt,
                        size: 56,
                        color: AppColors.mutedText(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '收藏列表没有重复歌曲',
                        style: TextStyle(
                          color: AppColors.mutedText(context),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final selected = _selectionFor(groups);
              return ListView.separated(
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _buildGroup(context, groups[index], groups, selected),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _appBarActions(List<DuplicateGroup> groups) {
    if (groups.isEmpty) return const [];
    final selected = _selectionFor(groups);
    return [
      if (_userSelection != null)
        TextButton(
          onPressed: _removing
              ? null
              : () => setState(() => _userSelection = null),
          child: Text(
            '按推荐勾选',
            style: TextStyle(color: AppColors.accentOf(context)),
          ),
        ),
      TextButton.icon(
        onPressed: _removing || selected.isEmpty
            ? null
            : () => _removeSongIds(selected.toList(growable: false)),
        icon: const Icon(Icons.delete_outline, size: 16),
        label: Text(_removing ? '处理中…' : '移除已选'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentOf(context),
        ),
      ),
    ];
  }

  /// 重复检测仅针对收藏列表。
  List<DuplicateGroup> _detectGroups(List<Playlist> playlists) {
    final favorites = playlists.where((p) => p.id == 'favorites').toList();
    final songs = favorites.isEmpty
        ? const <MusicItem>[]
        : favorites.first.songs;
    final ids = songs.map((s) => s.identityKey).toSet();
    return DuplicateDetector(songs: songs, favoriteIds: ids).detect();
  }

  Set<String> _selectionFor(List<DuplicateGroup> groups) {
    if (_userSelection != null) return _userSelection!;
    return {
      for (final group in groups)
        for (final song in group.redundantSongs) song.identityKey,
    };
  }

  Widget _buildGroup(
    BuildContext context,
    DuplicateGroup group,
    List<DuplicateGroup> groups,
    Set<String> selected,
  ) {
    final groupSelected = [
      for (final song in group.songs)
        if (selected.contains(song.identityKey)) song.identityKey,
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onScaffold(context),
                      ),
                    ),
                    Text(
                      '${group.artist} · ${group.count} 个版本 · 勾选要移除的',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              FxIconButton(
                tooltip: '播放',
                icon: Icon(
                  Icons.play_arrow,
                  size: 22,
                  color: AppColors.accentOf(context),
                ),
                onPressed: () => ref
                    .read(playerServiceProvider)
                    .playPlaylist(
                      group.songs,
                      index: 0,
                      manualPlayName: group.songs.first.name,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final song in group.songs)
            _buildSongRow(context, group, song, groups, selected),
          if (groupSelected.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _removing
                    ? null
                    : () => _removeSongIds(groupSelected),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(_removing ? '处理中…' : '移除本组已选'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSongRow(
    BuildContext context,
    DuplicateGroup group,
    MusicItem song,
    List<DuplicateGroup> groups,
    Set<String> selected,
  ) {
    final isBest = song.identityKey == group.bestSong.identityKey;
    final isSelected = selected.contains(song.identityKey);
    final accent = AppColors.accentOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _removing ? null : () => _toggleSelected(song, groups),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                activeColor: accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: _removing
                    ? null
                    : (_) => _toggleSelected(song, groups),
              ),
              AnimatedIconSwitch(
                icon: isBest ? Icons.star : Icons.music_note,
                keyValue: isBest ? Icons.star : Icons.music_note,
                size: 18,
                color: isBest ? accent : AppColors.mutedText(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _songLabel(song),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.onScaffold(context),
                  ),
                ),
              ),
              if (isBest)
                Text(
                  '推荐保留',
                  style: TextStyle(fontSize: 11, color: accent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _songLabel(MusicItem song) {
    final platform = song.platform.toUpperCase();
    return '${song.name} · $platform'
        '${(song.lyricsUrl?.isNotEmpty ?? false) ? ' · 有歌词' : ''}';
  }

  void _toggleSelected(MusicItem song, List<DuplicateGroup> groups) {
    setState(() {
      final next = {..._selectionFor(groups)};
      if (!next.add(song.identityKey)) {
        next.remove(song.identityKey);
      }
      _userSelection = next;
    });
  }

  Future<void> _removeSongIds(List<String> songIds) async {
    if (songIds.isEmpty) return;
    setState(() => _removing = true);
    try {
      final service = ref.read(playlistServiceProvider);
      final removed = await service.removeSongsFromPlaylist(
        'favorites',
        songIds,
      );
      if (!mounted) return;
      setState(() {
        final leftover = _userSelection;
        if (leftover != null) {
          leftover.removeAll(songIds);
          if (leftover.isEmpty) _userSelection = null;
        }
      });
      showAppNotification(
        '已移除 $removed 处重复项',
        type: AppNotificationType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppNotification('移除失败: $e', type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }
}
