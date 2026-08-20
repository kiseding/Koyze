import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../player/domain/music_item.dart';
import 'playlist_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/koyze_sheet.dart';

/// 歌单选择器 BottomSheet
/// 用于将歌曲添加到指定歌单
Future<void> showPlaylistPicker({
  required BuildContext context,
  required WidgetRef ref,
  required MusicItem song,
}) {
  return showKoyzeSheet(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (context) => _PlaylistPickerContent(song: song),
  );
}

class _PlaylistPickerContent extends ConsumerStatefulWidget {
  final MusicItem song;
  const _PlaylistPickerContent({required this.song});

  @override
  ConsumerState<_PlaylistPickerContent> createState() =>
      _PlaylistPickerContentState();
}

class _PlaylistPickerContentState
    extends ConsumerState<_PlaylistPickerContent> {
  final _newPlaylistController = TextEditingController();
  bool _showCreateField = false;

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  Future<void> _addToPlaylist(String playlistId) async {
    try {
      await ref.read(addSongToPlaylistProvider)(playlistId, widget.song);
      if (!mounted) return;
      Navigator.pop(context);
      showAppNotification('已添加到歌单', type: AppNotificationType.success);
    } catch (error) {
      if (!mounted) return;
      showAppNotification('添加失败: $error', type: AppNotificationType.error);
    }
  }

  Future<void> _createAndAdd() async {
    final name = _newPlaylistController.text.trim();
    if (name.isEmpty) return;
    try {
      await ref
          .read(playlistServiceProvider)
          .createPlaylist(name: name, songs: [widget.song]);
      if (!mounted) return;
      Navigator.pop(context);
      showAppNotification('已创建歌单并添加', type: AppNotificationType.success);
    } catch (error) {
      if (!mounted) return;
      showAppNotification('创建失败: $error', type: AppNotificationType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    final userPlaylists = playlists.where((p) => p.id != 'recent').toList();

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '添加到歌单',
                  style: TextStyle(
                    color: AppColors.onScaffold(context),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                FxIconButton(
                  tooltip: _showCreateField ? '收起新建歌单' : '新建歌单',
                  icon: Icon(
                    Icons.add,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () =>
                      setState(() => _showCreateField = !_showCreateField),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _showCreateField
                ? Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newPlaylistController,
                            style: TextStyle(
                              color: AppColors.onScaffold(context),
                            ),
                            decoration: InputDecoration(
                              hintText: '新歌单名称',
                              hintStyle: TextStyle(
                                color: AppColors.secondaryText(context),
                              ),
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onSubmitted: (_) async => _createAndAdd(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _createAndAdd,
                          child: Text(
                            '创建',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Divider(color: AppColors.fill(context)),
          ...userPlaylists.map(
            (playlist) => ListTile(
              leading: AnimatedIconSwitch(
                icon: playlist.id == 'favorites'
                    ? Icons.favorite
                    : Icons.queue_music,
                keyValue: playlist.id == 'favorites'
                    ? Icons.favorite
                    : Icons.queue_music,
                color: playlist.id == 'favorites'
                    ? AppColors.error
                    : AppColors.secondaryText(context),
              ),
              title: Text(
                playlist.name,
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              subtitle: Text(
                '${playlist.songCount} 首',
                style: TextStyle(
                  color: AppColors.secondaryText(context),
                  fontSize: 12,
                ),
              ),
              onTap: () async => _addToPlaylist(playlist.id),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
