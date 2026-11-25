import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../l10n/app_strings.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../domain/album_tracks.dart';
import 'album_tracks_provider.dart';
import 'search_provider.dart';

/// 专辑详情页。
///
/// 曲目优先来自平台专辑接口（完整、可播放），取不到时用 MusicBrainz
/// 的曲目表补全名称与顺序，最后才退回搜索命中结果。
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.albumName,
    required this.artistName,
    required this.albumId,
    required this.platform,
    required this.source,
    this.year,
  });

  final String albumName;
  final String artistName;
  final String albumId;
  final String platform;
  final String source;
  final int? year;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  AlbumQuery get _query => (
    album: widget.albumName,
    artist: widget.artistName,
    albumId: widget.albumId,
    platform: widget.platform,
    source: widget.source,
    year: widget.year,
  );

  /// MusicBrainz 曲目正在回平台匹配音源的那一行（用曲目序号标记）。
  int? _matching;

  String get _platformId =>
      widget.source.isNotEmpty ? widget.source : widget.platform;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tracks = ref.watch(albumTracksProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.albumName.isEmpty
              ? S.of(context).unknownAlbum
              : widget.albumName,
          overflow: TextOverflow.ellipsis,
        ),
        leading: FxIconButton(
          tooltip: S.of(context).back,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          tracks.maybeWhen(
            data: (list) => list.playable && list.songs.isNotEmpty
                ? TextButton.icon(
                    onPressed: () => _playFrom(list.songs, 0),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(S.of(context).playAll),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: tracks.when(
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
                  onPressed: () => ref.invalidate(albumTracksProvider(_query)),
                  child: Text(S.of(context).retry),
                ),
              ],
            ),
          ),
        ),
        data: (list) {
          if (list.songs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  S.of(context).albumTracksEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AlbumSummary(list: list),
              if (list.origin == AlbumTracksOrigin.musicBrainz)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: AppColors.mutedText(context),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          S.of(context).albumTracksMatchHint,
                          style: TextStyle(
                            color: AppColors.mutedText(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: list.songs.length,
                  itemBuilder: (context, index) {
                    final song = list.songs[index];
                    return _AlbumTrackRow(
                      song: song,
                      index: index,
                      busy: _matching == index,
                      onTap: () => _onTrackTap(list, index),
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

  Future<void> _onTrackTap(AlbumTrackList list, int index) async {
    if (list.playable) {
      _playFrom(list.songs, index);
      return;
    }
    // MusicBrainz 曲目只有元数据：回平台按歌名匹配一次再播。
    if (_matching != null) return;
    setState(() => _matching = index);
    final track = list.songs[index];
    try {
      final resolved = await resolveMusicBrainzTrack(
        ref.read(musicSourceServiceProvider),
        track: track,
        artistName: list.artistName,
        platformId: _platformId,
      );
      if (!mounted) return;
      if (resolved == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(S.of(context).albumTracksEmpty)));
        return;
      }
      await ref
          .read(playerServiceProvider)
          .setQueue([resolved], startIndex: 0, manualPlayName: resolved.name);
    } finally {
      if (mounted) setState(() => _matching = null);
    }
  }

  void _playFrom(List<MusicItem> songs, int index) {
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

class _AlbumSummary extends StatelessWidget {
  const _AlbumSummary({required this.list});

  final AlbumTrackList list;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final artwork = list.songs
        .map((song) => song.artwork)
        .firstWhere((url) => url != null && url.isNotEmpty, orElse: () => null);
    final year = list.year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: artwork == null
                ? Container(
                    width: 64,
                    height: 64,
                    color: AppColors.cardAlt(context),
                    child: Icon(
                      Icons.album_rounded,
                      color: AppColors.secondaryText(context),
                      size: 26,
                    ),
                  )
                : ArtworkImage(
                    artwork,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list.albumName.isEmpty
                      ? S.of(context).unknownAlbum
                      : list.albumName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onScaffold(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (list.artistName.isNotEmpty) list.artistName,
                    if (year != null) '$year',
                    '${list.songs.length} ${S.of(context).songs}',
                    if (list.origin == AlbumTracksOrigin.musicBrainz)
                      S.of(context).albumTracksFromMusicBrainz,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.secondaryText(context),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (list.playable) Icon(Icons.album_rounded, size: 18, color: accent),
        ],
      ),
    );
  }
}

class _AlbumTrackRow extends ConsumerWidget {
  const _AlbumTrackRow({
    required this.song,
    required this.index,
    required this.busy,
    required this.onTap,
  });

  final MusicItem song;
  final int index;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      currentMusicProvider.select(
        (current) => current?.identityKey == song.identityKey,
      ),
    );
    final accent = AppColors.accentOf(context);
    final subtitle = song.singer.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.cardAlt(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      : playing
                      ? Icon(Icons.play_arrow_rounded, color: accent, size: 20)
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.secondaryText(context),
                            fontSize: 12,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
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
                      if (subtitle.isNotEmpty && subtitle != '未知歌手') ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
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
                if (song.duration > Duration.zero)
                  Text(
                    _formatDuration(song.duration),
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
