import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/card_play_button.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/pressable.dart';
import '../../player/presentation/player_provider.dart';
import '../domain/nas_config.dart';
import '../domain/nas_kind.dart';
import 'nas_provider.dart';

class NasLibraryScreen extends ConsumerWidget {
  const NasLibraryScreen({super.key, required this.kind});

  final NasKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(nasConnectedProvider(kind));
    final config = ref.watch(nasConfigProvider(kind));
    final playlistsAsync = ref.watch(nasPlaylistsProvider(kind));
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
            FxIconButton(
              tooltip: '刷新',
              icon: Icon(Icons.refresh, color: on),
              onPressed: () => ref.invalidate(nasPlaylistsProvider(kind)),
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
          : playlistsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _empty(
                context,
                icon: Icons.error_outline,
                title: '加载歌单失败',
                subtitle: '$error',
                actionLabel: '重试',
                onAction: () => ref.invalidate(nasPlaylistsProvider(kind)),
              ),
              data: (playlists) {
                if (playlists.isEmpty) {
                  return _empty(
                    context,
                    icon: Icons.library_music_outlined,
                    title: '服务器上还没有歌单',
                    subtitle: '当前已连接 ${config.hostLabel}',
                    actionLabel: '刷新',
                    onAction: () => ref.invalidate(nasPlaylistsProvider(kind)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: playlists.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return _PlaylistTile(
                      kind: kind,
                      playlist: playlist,
                      onOpen: () => context.push(
                        kind.playlistRoute(playlist.id),
                        extra: playlist.name,
                      ),
                      onPlay: () => _playPlaylist(ref, playlist),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _playPlaylist(WidgetRef ref, NasPlaylistInfo playlist) async {
    try {
      final songs = await ref
          .read(nasServiceProvider(kind))
          .getPlaylistSongs(playlist.id);
      if (songs.isEmpty) {
        showAppNotification('歌单是空的', type: AppNotificationType.info);
        return;
      }
      await ref
          .read(playerServiceProvider)
          .playPlaylist(songs, manualPlayName: songs.first.name);
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

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.kind,
    required this.playlist,
    required this.onOpen,
    required this.onPlay,
  });

  final NasKind kind;
  final NasPlaylistInfo playlist;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    return Pressable(
      borderRadius: BorderRadius.circular(14),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.fill(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: kind.accent.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(kind.icon, color: kind.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name.isEmpty ? '未命名歌单' : playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: on,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlist.songCount} 首歌曲',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            CardPlayButton(
              color: AppColors.accentOf(context),
              backgroundColor: AppColors.accentOf(context).withAlpha(28),
              onPressed: playlist.songCount > 0 ? onPlay : null,
              icon: Icon(
                Icons.play_arrow_rounded,
                color: AppColors.accentOf(context),
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
