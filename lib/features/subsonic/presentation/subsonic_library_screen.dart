import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/card_play_button.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/pressable.dart';
import '../../nas/domain/nas_kind.dart';
import '../../nas/domain/self_hosted_kind.dart';
import '../../nas/presentation/nas_provider.dart';
import '../../player/presentation/player_provider.dart';
import 'subsonic_provider.dart';

class SubsonicLibraryScreen extends ConsumerStatefulWidget {
  const SubsonicLibraryScreen({super.key});

  @override
  ConsumerState<SubsonicLibraryScreen> createState() =>
      _SubsonicLibraryScreenState();
}

class _SubsonicLibraryScreenState
    extends ConsumerState<SubsonicLibraryScreen> {
  SelfHostedKind _kind = SelfHostedKind.subsonic;
  bool _pickedInitial = false;

  void _pickInitialKind() {
    if (_pickedInitial) return;
    _pickedInitial = true;
    if (ref.read(subsonicConnectedProvider)) {
      _kind = SelfHostedKind.subsonic;
      return;
    }
    for (final kind in NasKind.values) {
      if (ref.read(nasConnectedProvider(kind))) {
        _kind = SelfHostedKind.fromNas(kind);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _pickInitialKind();
    final nasKind = _kind.nasKind;
    final subsonicConnected = ref.watch(subsonicConnectedProvider);
    final nasConnected =
        nasKind == null ? false : ref.watch(nasConnectedProvider(nasKind));
    final connected = nasKind == null ? subsonicConnected : nasConnected;
    final configHost = nasKind == null
        ? ref.watch(subsonicConfigProvider).hostLabel
        : ref.watch(nasConfigProvider(nasKind)).hostLabel;
    final AsyncValue<List<_LibraryPlaylist>> playlistsAsync = nasKind == null
        ? ref.watch(subsonicPlaylistsProvider).whenData(
            (playlists) => [
              for (final playlist in playlists)
                _LibraryPlaylist(
                  id: playlist.id,
                  name: playlist.name,
                  songCount: playlist.songCount,
                ),
            ],
          )
        : ref.watch(nasPlaylistsProvider(nasKind)).whenData(
            (playlists) => [
              for (final playlist in playlists)
                _LibraryPlaylist(
                  id: playlist.id,
                  name: playlist.name,
                  songCount: playlist.songCount,
                ),
            ],
          );
    final on = AppColors.onScaffold(context);
    final accent = AppColors.accentOf(context);

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
          '自建音乐库',
          style: TextStyle(color: on, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          FxIconButton(
            tooltip: '连接设置',
            icon: Icon(Icons.settings_outlined, color: on),
            onPressed: () =>
                context.push('/subsonic-settings', extra: _kind),
          ),
          if (connected)
            FxIconButton(
              tooltip: '刷新',
              icon: Icon(Icons.refresh, color: on),
              onPressed: () {
                if (nasKind == null) {
                  ref.invalidate(subsonicPlaylistsProvider);
                } else {
                  ref.invalidate(nasPlaylistsProvider(nasKind));
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in SelfHostedKind.values)
                  ChoiceChip(
                    label: Text(kind.chipLabel),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                    selectedColor: accent.withAlpha(40),
                    labelStyle: TextStyle(
                      color: _kind == kind ? accent : on,
                      fontSize: 13,
                      fontWeight:
                          _kind == kind ? FontWeight.w600 : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color:
                          _kind == kind ? accent : AppColors.cardBorder(context),
                    ),
                    backgroundColor: AppColors.miniBar(context),
                    showCheckmark: false,
                  ),
              ],
            ),
          ),
          Expanded(
            child: !connected
                ? _empty(
                    context,
                    icon: Icons.cloud_off_outlined,
                    title: '尚未连接 ${_kind.title}',
                    subtitle: _kind.intro,
                    actionLabel: '去连接',
                    onAction: () => context.push('/subsonic-settings', extra: _kind),
                  )
                : playlistsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _empty(
                      context,
                      icon: Icons.error_outline,
                      title: '加载歌单失败',
                      subtitle: '$error',
                      actionLabel: '重试',
                      onAction: () {
                        if (nasKind == null) {
                          ref.invalidate(subsonicPlaylistsProvider);
                        } else {
                          ref.invalidate(nasPlaylistsProvider(nasKind));
                        }
                      },
                    ),
                    data: (items) {
                      if (items.isEmpty) {
                        return _empty(
                          context,
                          icon: Icons.library_music_outlined,
                          title: '服务器上还没有歌单',
                          subtitle: '当前已连接 $configHost',
                          actionLabel: '刷新',
                          onAction: () {
                            if (nasKind == null) {
                              ref.invalidate(subsonicPlaylistsProvider);
                            } else {
                              ref.invalidate(nasPlaylistsProvider(nasKind));
                            }
                          },
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final playlist = items[index];
                          return _PlaylistTile(
                            playlist: playlist,
                            icon: _kind.icon,
                            onOpen: () {
                              if (nasKind == null) {
                                context.push(
                                  '/subsonic/playlist/${Uri.encodeComponent(playlist.id)}',
                                  extra: playlist.name,
                                );
                              } else {
                                context.push(
                                  nasKind.playlistRoute(playlist.id),
                                  extra: playlist.name,
                                );
                              }
                            },
                            onPlay: () => _playPlaylist(playlist),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _playPlaylist(_LibraryPlaylist playlist) async {
    try {
      final nasKind = _kind.nasKind;
      final songs = nasKind == null
          ? await ref
              .read(subsonicServiceProvider)
              .getPlaylistSongs(playlist.id)
          : await ref
              .read(nasServiceProvider(nasKind))
              .getPlaylistSongs(playlist.id);
      if (songs.isEmpty) {
        showAppNotification('歌单是空的', type: AppNotificationType.info);
        return;
      }
      await ref.read(playerServiceProvider).playPlaylist(
            songs,
            manualPlayName: songs.first.name,
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

class _LibraryPlaylist {
  const _LibraryPlaylist({
    required this.id,
    required this.name,
    required this.songCount,
  });

  final String id;
  final String name;
  final int songCount;
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlist,
    required this.icon,
    required this.onOpen,
    required this.onPlay,
  });

  final _LibraryPlaylist playlist;
  final IconData icon;
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
                color: const Color(0xFF0A84FF).withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF0A84FF)),
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
