import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koyze/l10n/app_strings.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/adaptive_song_list.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../download/presentation/download_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../nas/domain/nas_library_groups.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';

/// 专辑 / 艺术家 / 文件夹的详情页。三者结构一样，只是标题和来源不同。
class NasCollectionScreen extends ConsumerWidget {
  const NasCollectionScreen({super.key, required this.collection});

  final NasCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    final accent = AppColors.accentOf(context);
    final songs = collection.songs;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        leading: FxIconButton(
          tooltip: S.of(context).back,
          icon: Icon(Icons.arrow_back, color: on),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          collection.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: on,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          FxIconButton(
            tooltip: S.of(context).downloadCollection,
            icon: Icon(Icons.download_outlined, color: on),
            onPressed: () => _downloadAll(context, ref, songs),
          ),
          FxIconButton(
            tooltip: S.of(context).playAll,
            icon: Icon(Icons.play_circle_fill, color: accent, size: 28),
            onPressed: songs.isEmpty ? null : () => _play(ref, songs, 0),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: collection.artwork == null
                        ? ColoredBox(
                            color: AppGlass.fill(
                              context,
                              style: AppGlassStyle.regular,
                            ),
                            child: Icon(
                              Icons.album_outlined,
                              color: muted,
                              size: 30,
                            ),
                          )
                        : ArtworkImage(
                            collection.artwork!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.album_outlined,
                              color: muted,
                              size: 30,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collection.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: on,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (collection.subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          collection.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        S.of(context).songCountValue(songs.length),
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AdaptiveSongList.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
              landscapeItemExtent: 82,
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
                          ? Icon(Icons.music_note, color: muted)
                          : ArtworkImage(
                              song.artwork!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Icon(Icons.music_note, color: muted),
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
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  trailing: FavoriteButton(song: song),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _play(WidgetRef ref, List<MusicItem> songs, int index) async {
    if (songs.isEmpty) return;
    try {
      await ref
          .read(playerServiceProvider)
          .playPlaylist(
            songs,
            index: index,
            manualPlayName: songs[index].name,
          );
    } catch (_) {
      // 播放失败由播放器自己提示。
    }
  }

  Future<void> _downloadAll(
    BuildContext context,
    WidgetRef ref,
    List<MusicItem> songs,
  ) async {
    if (songs.isEmpty) return;
    try {
      // 和单曲下载用同一档下载音质；NAS 侧再按服务器设置映射成码率上限。
      final quality = ref.read(downloadQualityProvider);
      await ref
          .read(downloadServiceProvider)
          .addTasks(songs, quality: audioQualityToken(quality));
      ref.read(downloadVersionProvider.notifier).state++;
      if (context.mounted) {
        showAppNotification(S.of(context).downloadQueued(songs.length));
      }
    } catch (error) {
      if (context.mounted) {
        showAppNotification(
          '${S.of(context).downloadFailed}: $error',
          type: AppNotificationType.error,
        );
      }
    }
  }
}
