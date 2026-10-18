import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../../player/domain/music_item.dart';
import 'playlist_provider.dart';
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
  final _newPlaylistFocus = FocusNode();
  bool _showCreateField = false;

  @override
  void dispose() {
    _newPlaylistController.dispose();
    _newPlaylistFocus.dispose();
    super.dispose();
  }

  Future<void> _addToPlaylist(String playlistId) async {
    try {
      await ref.read(addSongToPlaylistProvider)(playlistId, widget.song);
      if (!mounted) return;
      Navigator.pop(context);
      showAppNotification(
        S.of(context).addedToPlaylist,
        type: AppNotificationType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        '${S.of(context).addFailed}: $error',
        type: AppNotificationType.error,
      );
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
      showAppNotification(
        S.of(context).playlistCreatedAndAdded,
        type: AppNotificationType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        '${S.of(context).createFailed}: $error',
        type: AppNotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    final userPlaylists = playlists.where((p) => p.id != 'recent').toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KoyzeSheetGrabber(),
        KoyzeSheetTitle(
          title: S.of(context).addToPlaylist,
          action: _buildCreateToggle(context),
          onClose: () => Navigator.pop(context),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _showCreateField
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: AppColors.fill(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.cardBorder(context),
                              width: 0.9,
                            ),
                          ),
                          child: TextField(
                            controller: _newPlaylistController,
                            focusNode: _newPlaylistFocus,
                            textInputAction: TextInputAction.done,
                            style: TextStyle(
                              color: AppColors.onScaffold(context),
                              fontSize: 14.5,
                            ),
                            decoration: InputDecoration(
                              hintText: S.of(context).newPlaylistName,
                              hintStyle: TextStyle(
                                color: AppColors.mutedText(context),
                                fontSize: 14.5,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                            ),
                            onSubmitted: (_) async => _createAndAdd(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _createAndAdd,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(64, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          backgroundColor: AppColors.accentOf(
                            context,
                          ).withValues(alpha: 0.14),
                          foregroundColor: AppColors.accentOf(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          S.of(context).create,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        ...userPlaylists.map(
          (playlist) => KoyzeSheetAction(
            icon: playlist.id == 'favorites'
                ? Icons.favorite_rounded
                : Icons.queue_music_rounded,
            label: S
                .of(context)
                .builtinPlaylistName(playlist.id, playlist.name),
            subtitle: S.of(context).playlistSongCount(playlist.songCount),
            tone: playlist.id == 'favorites' ? AppColors.error : null,
            onTap: () async => _addToPlaylist(playlist.id),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  /// 标题右侧的"新建歌单"圆钮：展开时变成收起。
  Widget _buildCreateToggle(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Semantics(
      button: true,
      label: _showCreateField
          ? S.of(context).collapseNewPlaylist
          : S.of(context).newPlaylist,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final shouldShow = !_showCreateField;
            setState(() => _showCreateField = shouldShow);
            if (shouldShow) {
              requestTextInput(
                context,
                _newPlaylistFocus,
                initialDelay: const Duration(milliseconds: 220),
                retryDelay: const Duration(milliseconds: 180),
              );
            }
          },
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(
                alpha: AppColors.isDark(context) ? 0.20 : 0.13,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _showCreateField ? Icons.close_rounded : Icons.add_rounded,
              size: 20,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}
