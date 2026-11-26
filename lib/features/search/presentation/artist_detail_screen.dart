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
import '../../playlist/presentation/playlist_provider.dart';
import '../domain/album_tracks.dart';
import '../domain/artist_albums.dart';
import '../domain/artist_songs.dart';
import 'album_tracks_provider.dart';
import 'artist_detail_provider.dart';
import 'search_provider.dart';

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
          final total = groups.fold<int>(0, (sum, g) => sum + g.songs.length);
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
                      '${S.of(context).albums} · ${groups.length}  ·  ${S.of(context).songs} · $total',
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
                  itemCount: groups.length,
                  itemBuilder: (context, index) => _ArtistAlbumSection(
                    group: groups[index],
                    artistName: artistName,
                    platformId: _platformId,
                    onPlay: (songs, songIndex) => _play(ref, songs, songIndex),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String get _platformId => source.isNotEmpty ? source : platform;

  void _playAll(WidgetRef ref, List<MusicItem> songs) {
    final ordered = groupSongsByAlbum(
      songs,
    ).expand((group) => group.songs).toList();
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

/// 一张专辑在歌手页里的整段内容：专辑头 + 该专辑的曲目。
///
/// 曲目优先用平台专辑接口拉到的完整列表（序号从 1 开始重新计数），
/// 拉不到或还在加载时先显示搜索命中的那几首，不会让整段空着。
class _ArtistAlbumSection extends ConsumerWidget {
  const _ArtistAlbumSection({
    required this.group,
    required this.artistName,
    required this.platformId,
    required this.onPlay,
  });

  final ArtistAlbumGroup group;
  final String artistName;
  final String platformId;
  final void Function(List<MusicItem> songs, int index) onPlay;

  /// 这一段里第一首带平台专辑 id 的歌决定用哪个专辑接口。
  String get _albumId {
    for (final song in group.songs) {
      final id = albumIdOf(song);
      if (id.isNotEmpty) return id;
    }
    return '';
  }

  Future<void> _playTrack(
    BuildContext context,
    WidgetRef ref,
    List<MusicItem> songs,
    int index,
  ) async {
    final song = songs[index];
    if (song.isPlayable) {
      onPlay(songs, index);
      return;
    }
    final service = ref.read(musicSourceServiceProvider);
    final match = await resolveMusicBrainzTrack(
      service,
      track: song,
      artistName: artistName,
      platformId: platformId,
    );
    if (!context.mounted || match == null) return;
    onPlay([match], 0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumId = _albumId;
    final async = ref.watch(
      artistAlbumTracksProvider((
        albumId: albumId,
        platform: platformId,
        album: group.name,
        artist: artistName,
      )),
    );
    final full = async.valueOrNull;
    final sourceSongs = (full != null && full.isNotEmpty) ? full : group.songs;
    final songs = sourceSongs
        .where(
          (song) =>
              song.source == 'musicbrainz' ||
              songsForArtist([song], artistName).isNotEmpty,
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AlbumHeader(
          group: group,
          coverUrl: _firstArtwork(songs) ?? _firstArtwork(group.songs),
          songCount: songs.length,
          loading: async.isLoading,
        ),
        for (var index = 0; index < songs.length; index++)
          _ArtistSongRow(
            song: songs[index],
            index: index,
            onTap: () => _playTrack(context, ref, songs, index),
          ),
      ],
    );
  }
}

String? _firstArtwork(List<MusicItem> songs) {
  for (final song in songs) {
    final artwork = song.artwork;
    if (artwork != null && artwork.isNotEmpty) return artwork;
  }
  return null;
}

class _AlbumHeader extends ConsumerWidget {
  const _AlbumHeader({
    required this.group,
    required this.coverUrl,
    required this.songCount,
    required this.loading,
  });

  final ArtistAlbumGroup group;
  final String? coverUrl;
  final int songCount;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppColors.accentOf(context);
    final favorites =
        ref.watch(favoriteSongsProvider).valueOrNull ?? const <MusicItem>[];
    final albumSongs = group.songs.where((song) => song.isPlayable).toList();
    final albumFavorited =
        albumSongs.isNotEmpty &&
        albumSongs.every((song) => isFavoriteMusic(song, favorites));
    final time = group.time;
    final releaseDate = time == null
        ? null
        : '${time.year} 年 ${time.month.toString().padLeft(2, '0')} 月';
    final name = group.name.trim().isEmpty
        ? S.of(context).unknownAlbum
        : group.name;
    final cover = coverUrl;
    final subtitle = [
      if (releaseDate != null) releaseDate,
      '${S.of(context).songs} $songCount',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Material(
        color: AppColors.card(context).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: cover == null || cover.isEmpty
                    ? const _ArtworkPlaceholder()
                    : ArtworkImage(
                        cover,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _ArtworkPlaceholder(),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onScaffold(context),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.secondaryText(context),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (loading) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: AppColors.mutedText(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: albumFavorited
                    ? S.of(context).unfavorite
                    : S.of(context).favorite,
                onPressed: albumSongs.isEmpty
                    ? null
                    : () async {
                        final toggle = ref.read(toggleFavoriteProvider);
                        for (final song in albumSongs) {
                          if (isFavoriteMusic(song, favorites) !=
                              albumFavorited) {
                            await toggle(song);
                          }
                        }
                        ref.invalidate(favoriteSongsProvider);
                      },
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  albumFavorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 19,
                  color: albumFavorited
                      ? accent
                      : AppColors.secondaryText(context),
                ),
              ),
            ],
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
    final favoriteSongs =
        ref.watch(favoriteSongsProvider).valueOrNull ?? const <MusicItem>[];
    final isFavorite = isFavoriteMusic(song, favoriteSongs);
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
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: playing ? accent : AppColors.onScaffold(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isFavorite
                      ? S.of(context).unfavorite
                      : S.of(context).favorite,
                  onPressed: () async {
                    await ref.read(toggleFavoriteProvider)(song);
                    ref.invalidate(favoriteSongsProvider);
                  },
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 19,
                    color: isFavorite
                        ? accent
                        : AppColors.secondaryText(context),
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
