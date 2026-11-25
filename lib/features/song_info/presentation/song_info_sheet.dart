import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../../stats/presentation/play_history_provider.dart';
import '../domain/song_comment.dart';
import 'song_info_provider.dart';

/// 「关于这首歌」面板。
///
/// 歌曲标签与播放记忆始终独立展示；网易歌曲另附公开评论和相似歌曲。
Future<void> showSongInfoSheet(BuildContext context, MusicItem music) {
  return showKoyzeSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SongInfoSheet(music: music),
  );
}

class SongInfoSheet extends ConsumerWidget {
  const SongInfoSheet({super.key, required this.music});

  final MusicItem music;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final songId = neteaseIdOf(music);
    final muted = AppColors.mutedText(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoyzeSheetTitle(
          title: s.songInfo,
          subtitle: [music.name, music.singer]
              .where((v) => v.trim().isNotEmpty)
              .join(' · '),
          onClose: () => Navigator.pop(context),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              _TagCard(music: music),
              const SizedBox(height: 12),
              _MemoryCard(music: music),
              if (songId == null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    s.songInfoEmpty,
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                )
              else ...[
                const SizedBox(height: 22),
                _CommentsSection(songId: songId),
                const SizedBox(height: 22),
                _SimilarSection(songId: songId),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TagCard extends StatelessWidget {
  const _TagCard({required this.music});

  final MusicItem music;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);
    final meta = music.meta ?? const <String, dynamic>{};
    final rows = <String, String>{
      s.songInfoTitle: music.name,
      s.songInfoArtist: music.singer,
      if (music.album.trim().isNotEmpty) s.songInfoAlbum: music.album,
      if (music.duration > Duration.zero)
        s.songInfoDuration: _formatDuration(music.duration),
      if (meta['ext']?.toString().trim().isNotEmpty == true)
        s.songInfoFormat: meta['ext'].toString().toUpperCase(),
      if (meta['bitrate'] is num && (meta['bitrate'] as num) > 0)
        s.songInfoBitrate: '${((meta['bitrate'] as num) / 1000).round()} kbps',
      if (meta['localActualQuality']?.toString().trim().isNotEmpty == true)
        s.songInfoQuality: meta['localActualQuality'].toString(),
    };
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sell_outlined, size: 15, color: AppColors.accentOf(context)),
              const SizedBox(width: 6),
              Text(s.songInfoTags, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.accentOf(context))),
            ],
          ),
          const SizedBox(height: 9),
          for (final entry in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 44, child: Text(entry.key, style: TextStyle(fontSize: 11.5, color: secondary))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(entry.value, style: TextStyle(fontSize: 12.5, color: primary))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 本地播放历史算出的「回忆坐标」。
class _MemoryCard extends ConsumerWidget {
  const _MemoryCard({required this.music});

  final MusicItem music;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    ref.watch(playHistoryRevisionProvider);
    final entries = ref
        .read(playHistoryStoreProvider)
        .entries
        .where((entry) => entry.songId == music.id)
        .toList(growable: false);

    final accent = AppColors.accentOf(context);
    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          '${s.songInfoMemory} · ${s.songInfoMemoryEmpty}',
          style: TextStyle(fontSize: 11.5, color: secondary),
        ),
      );
    }

    final first = entries.reduce(
      (a, b) => a.playedAt.isBefore(b.playedAt) ? a : b,
    );
    final seconds = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.listenedSec,
    );
    final minutes = (seconds / 60).round();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place_outlined, size: 15, color: accent),
              const SizedBox(width: 6),
              Text(
                s.songInfoMemory,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatDate(first.playedAt),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${entries.length} 次 · $minutes 分钟',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

class _CommentsSection extends ConsumerWidget {
  const _CommentsSection({required this.songId});

  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final async = ref.watch(songCommentsProvider(songId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (_, _) => _Hint(text: s.checkNetwork),
          data: (page) {
            if (page == null || page.isEmpty) {
              return _Hint(text: s.songInfoEmpty);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  text: s.songInfoCommentsTotal(page.total),
                  trailing: page.hot.isEmpty
                      ? null
                      : Icon(
                          Icons.local_fire_department_outlined,
                          size: 15,
                          color: AppColors.mutedText(context),
                        ),
                ),
                for (final comment in page.hot.take(3))
                  _CommentTile(comment: comment, highlighted: true),
                if (page.hot.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Divider(
                      height: 1,
                      color: AppColors.cardBorder(context),
                    ),
                  ),
                for (final comment in page.latest.take(12))
                  _CommentTile(comment: comment),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, this.highlighted = false});

  final SongComment comment;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);
    final avatar = comment.avatarUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: avatar == null || avatar.isEmpty
                ? Container(
                    width: 30,
                    height: 30,
                    color: AppColors.fill(context),
                    child: Icon(
                      Icons.person_outline,
                      size: 16,
                      color: secondary,
                    ),
                  )
                : ArtworkImage(avatar, width: 30, height: 30, cacheWidth: 90),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: highlighted
                              ? AppColors.accentOf(context)
                              : secondary,
                        ),
                      ),
                    ),
                    if (comment.likedCount > 0) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.favorite,
                        size: 10,
                        color: secondary.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${comment.likedCount}',
                        style: TextStyle(fontSize: 10.5, color: secondary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                if (comment.hasReply)
                  Text(
                    '回复 ${comment.replyTo}：',
                    style: TextStyle(
                      fontSize: 11,
                      color: secondary.withValues(alpha: 0.8),
                    ),
                  ),
                Text(
                  comment.content,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: primary.withValues(alpha: 0.86),
                  ),
                ),
                if (comment.location != null && comment.location!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      comment.location!,
                      style: TextStyle(
                        fontSize: 10,
                        color: secondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimilarSection extends ConsumerWidget {
  const _SimilarSection({required this.songId});

  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final async = ref.watch(similarSongsProvider(songId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(text: s.songInfoSimilar),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (_, _) => _Hint(text: s.checkNetwork),
          data: (songs) {
            if (songs.isEmpty) return _Hint(text: s.songInfoEmpty);
            return Column(
              children: [
                for (var i = 0; i < songs.length; i++)
                  _SimilarRow(songs: songs, index: i),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SimilarRow extends ConsumerWidget {
  const _SimilarRow({required this.songs, required this.index});

  final List<MusicItem> songs;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = songs[index];
    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);
    final artwork = song.artwork;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        ref
            .read(playerServiceProvider)
            .playPlaylist(songs, index: index, userInitiated: true);
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: artwork == null || artwork.isEmpty
                  ? Container(
                      width: 40,
                      height: 40,
                      color: AppColors.fill(context),
                      child: Icon(Icons.music_note, size: 18, color: secondary),
                    )
                  : ArtworkImage(
                      artwork,
                      width: 40,
                      height: 40,
                      cacheWidth: 120,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: primary,
                    ),
                  ),
                  Text(
                    song.singer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: secondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.play_arrow_rounded, size: 18, color: secondary),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.onScaffold(context),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          color: AppColors.mutedText(context),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context), width: 0.8),
      ),
      child: child,
    );
  }
}
