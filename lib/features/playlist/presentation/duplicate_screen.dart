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
  final Set<String> _selectedSongIds = {};

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(hydratedPlaylistsProvider);
    final groups = playlistsAsync.valueOrNull == null
        ? null
        : _detectGroups(playlistsAsync.requireValue);

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      // 列表可滚动到栏内部（栏高度不变），顶栏磨砂才可见。
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        // 顶栏整栏磨砂玻璃，无底部渐变透明。
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
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
          if (_selectedSongIds.isNotEmpty)
            FxIconButton(
              tooltip: '删除已选歌曲',
              icon: const Icon(Icons.delete_outline),
              onPressed: _removing ? null : _removeSelected,
            ),
          if (groups != null && groups.isNotEmpty)
            TextButton.icon(
              onPressed: _removing ? null : () => _removeAllRedundant(groups),
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: Text(_removing ? '处理中…' : '一键移除'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentOf(context),
              ),
            ),
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
                  _buildGroup(context, groups[index]),
            );
          },
        ),
      ),
    );
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

  Widget _buildGroup(BuildContext context, DuplicateGroup group) {
    final playProvider = ref.read(playerServiceProvider);
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
                      '${group.artist} · ${group.count} 个版本',
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
                onPressed: () => playProvider.playPlaylist(
                  group.songs,
                  index: 0,
                  manualPlayName: group.songs.first.name,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final song in group.songs)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              selected: _selectedSongIds.contains(song.identityKey),
              selectedTileColor: AppColors.accentOf(context).withAlpha(24),
              onLongPress: () => _toggleSelected(song),
              onTap: _selectedSongIds.isEmpty
                  ? null
                  : () => _toggleSelected(song),
              leading: AnimatedIconSwitch(
                icon: song.identityKey == group.bestSong.identityKey
                    ? Icons.star
                    : Icons.music_note,
                keyValue: song.identityKey == group.bestSong.identityKey
                    ? Icons.star
                    : Icons.music_note,
                size: 18,
                color: song.identityKey == group.bestSong.identityKey
                    ? AppColors.accentOf(context)
                    : AppColors.mutedText(context),
              ),
              title: Text(
                _songLabel(song),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.onScaffold(context),
                ),
              ),
              trailing: song.identityKey == group.bestSong.identityKey
                  ? Text(
                      '推荐保留',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.accentOf(context),
                      ),
                    )
                  : null,
            ),
          if (group.redundantSongs.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _removing ? null : () => _removeRedundant(group),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(_removing ? '处理中…' : '移除其余版本'),
              ),
            ),
        ],
      ),
    );
  }

  String _songLabel(MusicItem song) {
    final platform = song.platform.toUpperCase();
    return '${song.name} · $platform'
        '${(song.lyricsUrl?.isNotEmpty ?? false) ? ' · 有歌词' : ''}';
  }

  Future<void> _removeRedundant(DuplicateGroup group) {
    return _removeSongIds(
      group.redundantSongs.map((s) => s.identityKey).toList(growable: false),
    );
  }

  void _toggleSelected(MusicItem song) {
    setState(() {
      if (!_selectedSongIds.add(song.identityKey)) {
        _selectedSongIds.remove(song.identityKey);
      }
    });
  }

  Future<void> _removeSelected() async {
    await _removeSongIds(_selectedSongIds.toList(growable: false));
  }

  Future<void> _removeAllRedundant(List<DuplicateGroup> groups) {
    final ids = <String>{};
    for (final group in groups) {
      for (final song in group.redundantSongs) {
        ids.add(song.identityKey);
      }
    }
    return _removeSongIds(ids.toList(growable: false));
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
      _selectedSongIds.removeAll(songIds);
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
