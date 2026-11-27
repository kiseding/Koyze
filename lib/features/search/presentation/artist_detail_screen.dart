import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/adaptive_song_list.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
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

class ArtistDetailScreen extends ConsumerStatefulWidget {
  const ArtistDetailScreen({
    super.key,
    required this.artistName,
    required this.platform,
    required this.source,
  });

  final String artistName;
  final String platform;
  final String source;

  @override
  ConsumerState<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends ConsumerState<ArtistDetailScreen> {
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0);
  List<MusicItem>? _groupSource;
  List<ArtistAlbumGroup> _albumGroups = const [];
  final Map<String, bool> _expandedAlbums = <String, bool>{};

  List<ArtistAlbumGroup> _groupsFor(List<MusicItem> songs) {
    if (!identical(_groupSource, songs)) {
      _groupSource = songs;
      _albumGroups = groupSongsByAlbum(songs);
    }
    return _albumGroups;
  }

  String _albumSectionKey(ArtistAlbumGroup group) {
    final first = group.songs.isEmpty ? '' : group.songs.first.identityKey;
    final last = group.songs.isEmpty ? '' : group.songs.last.identityKey;
    return '$_platformId:${group.name}:${group.songs.length}:$first:$last';
  }

  ArtistQuery get _query => (
    name: widget.artistName,
    platform: widget.platform,
    source: widget.source,
  );

  String get _platformId =>
      widget.source.isNotEmpty ? widget.source : widget.platform;

  @override
  void dispose() {
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(artistSongsProvider(_query));
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(widget.artistName),
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
        flexibleSpace: ValueListenableBuilder<double>(
          valueListenable: _scrollOffset,
          builder: (context, offset, _) {
            final frost = ((offset - 2) / 72).clamp(0.0, 1.0);
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Theme.of(
                      context,
                    ).scaffoldBackgroundColor.withValues(alpha: 0.72 * frost),
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 16 * frost,
                      sigmaY: 16 * frost,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ],
              ),
            );
          },
        ),
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
          final groups = _groupsFor(items);
          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _scrollOffset.value = notification.metrics.pixels;
              return false;
            },
            child: AdaptiveSongList.builder(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.paddingOf(context).top + koyzeToolbarHeight + 8,
                16,
                16,
              ),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final key = _albumSectionKey(group);
                return _ArtistAlbumSection(
                  key: ValueKey<String>(key),
                  group: group,
                  artistName: widget.artistName,
                  platformId: _platformId,
                  expanded: _expandedAlbums.putIfAbsent(key, () => true),
                  onExpandedChanged: (value) {
                    _expandedAlbums[key] = value;
                  },
                  onPlay: (songs, songIndex) => _play(ref, songs, songIndex),
                );
              },
            ),
          );
        },
      ),
    );
  }

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

/// 一张专辑及其可折叠曲目列表。
class _ArtistAlbumSection extends ConsumerStatefulWidget {
  const _ArtistAlbumSection({
    super.key,
    required this.group,
    required this.artistName,
    required this.platformId,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onPlay,
  });

  final ArtistAlbumGroup group;
  final String artistName;
  final String platformId;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final void Function(List<MusicItem> songs, int index) onPlay;

  @override
  ConsumerState<_ArtistAlbumSection> createState() =>
      _ArtistAlbumSectionState();
}

class _ArtistAlbumSectionState extends ConsumerState<_ArtistAlbumSection> {
  late bool _expanded = widget.expanded;
  List<MusicItem>? _sourceSongs;
  String? _filteredArtist;

  @override
  void didUpdateWidget(covariant _ArtistAlbumSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) {
      _expanded = widget.expanded;
    }
  }

  List<MusicItem> _filteredSongs = const [];

  String get _albumId {
    for (final song in widget.group.songs) {
      final id = albumIdOf(song);
      if (id.isNotEmpty) return id;
    }
    return '';
  }

  Future<void> _playTrack(
    BuildContext context,
    List<MusicItem> songs,
    int index,
  ) async {
    final song = songs[index];
    if (song.isPlayable) {
      widget.onPlay(songs, index);
      return;
    }
    final service = ref.read(musicSourceServiceProvider);
    final match = await resolveMusicBrainzTrack(
      service,
      track: song,
      artistName: widget.artistName,
      platformId: widget.platformId,
    );
    if (!context.mounted || match == null) return;
    widget.onPlay([match], 0);
  }

  @override
  Widget build(BuildContext context) {
    final albumId = _albumId;
    final async = ref.watch(
      artistAlbumTracksProvider((
        albumId: albumId,
        platform: widget.platformId,
        album: widget.group.name,
        artist: widget.artistName,
      )),
    );
    final full = async.valueOrNull;
    final sourceSongs = (full != null && full.isNotEmpty)
        ? full
        : widget.group.songs;
    if (!identical(_sourceSongs, sourceSongs) ||
        _filteredArtist != widget.artistName) {
      _sourceSongs = sourceSongs;
      _filteredArtist = widget.artistName;
      _filteredSongs = sourceSongs
          .where(
            (song) =>
                song.source == 'musicbrainz' ||
                songsForArtist([song], widget.artistName).isNotEmpty,
          )
          .toList(growable: false);
    }
    final songs = _filteredSongs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.card(context).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _AlbumHeader(
              group: widget.group,
              coverUrl:
                  _firstArtwork(songs) ?? _firstArtwork(widget.group.songs),
              songCount: songs.length,
              loading: async.isLoading,
              expanded: _expanded,
              onTap: () {
                final next = !_expanded;
                setState(() => _expanded = next);
                widget.onExpandedChanged(next);
              },
              onFavorite: () => _toggleAlbumFavorite(songs),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      children: [
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: 14,
                          endIndent: 14,
                          color: AppColors.secondaryText(
                            context,
                          ).withValues(alpha: 0.14),
                        ),
                        for (var index = 0; index < songs.length; index++)
                          _ArtistSongRow(
                            song: songs[index],
                            index: index,
                            onTap: () => _playTrack(context, songs, index),
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAlbumFavorite(List<MusicItem> songs) async {
    final favorites =
        ref.read(favoriteSongsProvider).valueOrNull ?? const <MusicItem>[];
    final playable = songs.where((song) => song.isPlayable).toList();
    if (playable.isEmpty) return;
    final allFavorited = playable.every(
      (song) => isFavoriteMusic(song, favorites),
    );
    final toggle = ref.read(toggleFavoriteProvider);
    for (final song in playable) {
      if (isFavoriteMusic(song, favorites) == allFavorited) {
        await toggle(song);
      }
    }
    ref.invalidate(favoriteSongsProvider);
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
    required this.expanded,
    required this.onTap,
    required this.onFavorite,
  });

  final ArtistAlbumGroup group;
  final String? coverUrl;
  final int songCount;
  final bool loading;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
            SizedBox(
              width: 44,
              height: 48,
              child: IconButton(
                tooltip: albumFavorited
                    ? S.of(context).unfavorite
                    : S.of(context).favorite,
                onPressed: albumSongs.isEmpty ? null : onFavorite,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 48,
                ),
                icon: Icon(
                  albumFavorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 23,
                  color: albumFavorited
                      ? accent
                      : AppColors.secondaryText(context),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 20,
              color: AppColors.secondaryText(context),
            ),
          ],
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
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
            SizedBox(
              width: 44,
              height: 40,
              child: IconButton(
                tooltip: isFavorite
                    ? S.of(context).unfavorite
                    : S.of(context).favorite,
                onPressed: () async {
                  await ref.read(toggleFavoriteProvider)(song);
                  ref.invalidate(favoriteSongsProvider);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 40,
                ),
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 21,
                  color: isFavorite ? accent : AppColors.secondaryText(context),
                ),
              ),
            ),
          ],
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
