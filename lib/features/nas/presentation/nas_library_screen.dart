import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../domain/nas_kind.dart';
import 'nas_provider.dart';

class NasLibraryScreen extends ConsumerWidget {
  const NasLibraryScreen({super.key, required this.kind});

  final NasKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(nasConnectedProvider(kind));
    final config = ref.watch(nasConfigProvider(kind));
    final songsAsync = ref.watch(nasLibrarySongsProvider(kind));
    final on = AppColors.onScaffold(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: FxIconButton(
          tooltip: '返回',
          icon: Icon(Icons.arrow_back, color: on),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          kind.libraryTitle,
          style: TextStyle(color: on, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          FxIconButton(
            tooltip: '连接设置',
            icon: Icon(Icons.settings_outlined, color: on),
            onPressed: () => context.push(kind.settingsRoute),
          ),
          if (connected)
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
          if (connected)
            FxIconButton(
              tooltip: '刷新',
              icon: Icon(Icons.refresh, color: on),
              onPressed: () => ref.invalidate(nasLibrarySongsProvider(kind)),
            ),
        ],
      ),
      body: !connected
          ? _empty(
              context,
              icon: Icons.cloud_off_outlined,
              title: '尚未连接 ${kind.title}',
              subtitle: kind.settingsSubtitle,
              actionLabel: '去连接',
              onAction: () => context.push(kind.settingsRoute),
            )
          : songsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _empty(
                context,
                icon: Icons.error_outline,
                title: '加载歌曲失败',
                subtitle: '$error',
                actionLabel: '重试',
                onAction: () => ref.invalidate(nasLibrarySongsProvider(kind)),
              ),
              data: (songs) {
                if (songs.isEmpty) {
                  return _empty(
                    context,
                    icon: Icons.library_music_outlined,
                    title: '服务器上还没有歌曲',
                    subtitle: '当前已连接 ${config.hostLabel}',
                    actionLabel: '刷新',
                    onAction: () =>
                        ref.invalidate(nasLibrarySongsProvider(kind)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
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
                        [
                          if (song.singer.trim().isNotEmpty) song.singer,
                          if (song.album.trim().isNotEmpty) song.album,
                        ].join(' · '),
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
    if (songs.isEmpty) return;
    try {
      await ref.read(playerServiceProvider).playPlaylist(
            songs,
            index: index,
            manualPlayName: songs[index].name,
          );
    } catch (error) {
      showAppNotification('播放失败: $error', type: AppNotificationType.error);
    }
  }

  Widget _empty(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final muted = AppColors.mutedText(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onScaffold(context),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
