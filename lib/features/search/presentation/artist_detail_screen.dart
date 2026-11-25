import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/adaptive_song_list.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../l10n/app_strings.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../domain/artist_albums.dart';
import 'artist_detail_provider.dart';

class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({
    super.key,
    required this.artistName,
    required this.platform,
    required this.source,
  });

  final String artistName;
  final String platform;
  final String source;

  ArtistQuery get _query =>
      (name: artistName, platform: platform, source: source);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(artistSongsProvider(_query));
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(artistName),
        leading: FxIconButton(
          tooltip: S.of(context).back,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          songs.maybeWhen(
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : TextButton.icon(
                    onPressed: () => _playAll(ref, items),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(S.of(context).playAll),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: songs.when(
        loading: () => Center(
          child: AppLoadingIndicator(color: AppColors.accentOf(context)),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${S.of(context).loadFailed}: $error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.error),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(artistSongsProvider(_query)),
                  child: Text(S.of(context).retry),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                S.of(context).playlistEmpty,
                style: TextStyle(color: AppColors.mutedText(context)),
              ),
            );
          }
          final groups = groupSongsByAlbum(items);
          final ordered = groups.expand((group) => group.songs).toList();
          final entries = <_ArtistListEntry>[];
          var songIndex = 0;
          for (final group in groups) {
            entries.add(_ArtistListEntry.album(group, songIndex));
            for (final song in group.songs) {
              entries.add(_ArtistListEntry.song(song, songIndex));
              songIndex++;
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: AppColors.accentOf(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${S.of(context).albums} · ${groups.length}  ·  ${S.of(context).songs} · ${ordered.length}',
                      style: TextStyle(
                        color: AppColors.secondaryText(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AdaptiveSongList.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final album = entry.album;
                    if (album != null) {
                      return _AlbumHeader(
                        group: album,
                        onTap: () => _play(ref, ordered, entry.order),
                      );
                    }
                    final song = entry.song!;
                    return _ArtistSongRow(
                      song: song,
                      index: entry.order,
                      onTap: () => _play(ref, ordered, entry.order),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _playAll(WidgetRef ref, List<MusicItem> songs) {
    final ordered = groupSongsByAlbum(songs)
        .expand((group) => group.songs)
        .toList();
    _play(ref, ordered, 0);
  }

  void _play(WidgetRef ref, List<MusicItem> songs, int index) {
    final playable = songs.where((song) => song.isPlayable).toList();
    if (playable.isEmpty) return;
    final selected = songs[index];
    final playableIndex = playable.indexWhere(
      (song) => song.identityKey == selected.identityKey,
    );
    ref
        .read(playerServiceProvider)
        .setQueue(
          playable,
          startIndex: playableIndex < 0 ? 0 : playableIndex,
          manualPlayName: selected.name,
        );
  }
}

class _ArtistListEntry {
  const _ArtistListEntry.album(this.album, this.order) : song = null;
  const _ArtistListEntry.song(this.song, this.order) : album = null;

  final ArtistAlbumGroup? album;
  final MusicItem? song;
  final int order;
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({required this.group, required this.onTap});

  final ArtistAlbumGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final year = group.time?.year;
    final name = group.name.trim().isEmpty
        ? S.of(context).unknownAlbum
        : group.name;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Material(
        color: AppColors.card(context).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.album_rounded, size: 18, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (year != null) ...[
                  Text(
                    '$year',
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  '${group.songs.length}',
                  style: TextStyle(
                    color: AppColors.secondaryText(context),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.play_arrow_rounded,
                  size: 16,
                  color: accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistSongRow extends ConsumerWidget {
  const _ArtistSongRow({
    required this.song,
    required this.index,
    required this.onTap,
  });

  final MusicItem song;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      currentMusicProvider.select(
        (current) => current?.identityKey == song.identityKey,
      ),
    );
    final accent = AppColors.accentOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.cardAlt(context).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: playing
                      ? Icon(Icons.play_arrow_rounded, color: accent, size: 21)
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.secondaryText(context),
                            fontSize: 12,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: song.artwork == null || song.artwork!.isEmpty
                      ? const _ArtworkPlaceholder()
                      : ArtworkImage(
                          song.artwork!,
                          width: 42,
                          height: 42,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const _ArtworkPlaceholder(),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: playing
                              ? accent
                              : AppColors.onScaffold(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (song.album.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          song.album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.secondaryText(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    color: AppColors.cardAlt(context),
    child: Icon(
      Icons.music_note_rounded,
      color: AppColors.secondaryText(context),
      size: 20,
    ),
  );
}
