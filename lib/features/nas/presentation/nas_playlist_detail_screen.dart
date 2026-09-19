import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../domain/nas_kind.dart';
import 'nas_provider.dart';

class NasPlaylistDetailScreen extends ConsumerWidget {
  const NasPlaylistDetailScreen({
    super.key,
    required this.kind,
    required this.playlistId,
    this.playlistName,
  });

  final NasKind kind;
  final String playlistId;
  final String? playlistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(
      nasPlaylistSongsProvider(NasPlaylistSongsKey(kind, playlistId)),
    );
    final on = AppColors.onScaffold(context);
    final title = playlistName?.trim().isNotEmpty == true
        ? playlistName!
        : '${kind.title} 歌单';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        leading: FxIconButton(
          tooltip: '返回',
          icon: Icon(Icons.arrow_back, color: on),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: TextStyle(color: on, fontSize: 18),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          songsAsync.maybeWhen(
            data: (songs) => songs.isEmpty
                ? const SizedBox.shrink()
                : FxIconButton(
                    tooltip: '播放全部',
                    icon: Icon(
                      Icons.play_circle_fill,
                      color: AppColors.accentOf(context),
                      size: 28,
                    ),
                    onPressed: () => _play(ref, songs, 0),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: songsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '加载失败: $error',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
        ),
        data: (songs) {
          if (songs.isEmpty) {
            return Center(
              child: Text(
                '歌单是空的',
                style: TextStyle(color: AppColors.mutedText(context)),
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
              bottom: 32,
            ),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return ListTile(
                onTap: () => _play(ref, songs, index),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: song.artwork == null || song.artwork!.isEmpty
                        ? Icon(
                            Icons.music_note,
                            color: AppColors.mutedText(context),
                          )
                        : ArtworkImage(
                            song.artwork!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.music_note,
                              color: AppColors.mutedText(context),
                            ),
                          ),
                  ),
                ),
                title: Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: on, fontSize: 14),
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
                trailing: FavoriteButton(song: song),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _play(WidgetRef ref, List<MusicItem> songs, int index) async {
    try {
      await ref
          .read(playerServiceProvider)
          .playPlaylist(
            songs,
            index: index,
            manualPlayName: songs[index].name,
          );
    } catch (error) {
      showAppNotification('播放失败: $error', type: AppNotificationType.error);
    }
  }
}
