import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/music_source_service.dart';
import '../domain/album_tracks.dart';
import '../../player/domain/music_item.dart';
import '../domain/artist_songs.dart';
import 'artist_detail_provider.dart';
import 'search_provider.dart';

/// 专辑详情页的查询参数。
///
/// [albumId] 是平台自己的专辑 id（来自歌手页分组的歌曲 meta）；
/// 本地/收藏等没有平台 id 的场景传空串，直接走 MusicBrainz / 搜索兜底。
typedef AlbumQuery = ({
  String album,
  String artist,
  String albumId,
  String platform,
  String source,
  int? year,
});

class AlbumTrackList {
  const AlbumTrackList({
    required this.songs,
    required this.origin,
    required this.albumName,
    required this.artistName,
    this.year,
  });

  final List<MusicItem> songs;
  final AlbumTracksOrigin origin;
  final String albumName;
  final String artistName;
  final int? year;

  /// 平台接口或搜索兜底拿到的曲目可以直接播放；
  /// MusicBrainz 曲目只有元数据，播放前要回平台匹配一次。
  bool get playable => origin != AlbumTracksOrigin.musicBrainz;
}

/// 专辑曲目：平台专辑接口优先，取不到再用 MusicBrainz 补全曲目表，
/// 最后才退回「歌手 + 专辑」搜索过滤。
final albumTracksProvider = FutureProvider.autoDispose
    .family<AlbumTrackList, AlbumQuery>((ref, query) async {
      final albumName = query.album.trim();
      final artistName = query.artist.trim();
      final platformId = query.source.isNotEmpty
          ? query.source
          : query.platform;
      final service = ref.watch(musicSourceServiceProvider);

      AlbumTrackList build(List<MusicItem> songs, AlbumTracksOrigin origin) =>
          AlbumTrackList(
            songs: songs,
            origin: origin,
            albumName: albumName,
            artistName: artistName,
            year: query.year,
          );

      if (albumName.isEmpty && query.albumId.isEmpty) {
        return build(const [], AlbumTracksOrigin.search);
      }

      // 1) 平台专辑接口：曲目完整、顺序正规，并且可直接播放。
      if (query.albumId.isNotEmpty) {
        final songs = await service.getAlbumSongs(
          query.albumId,
          sourceId: platformId,
        );
        if (songs.isNotEmpty) {
          return build(
            fillAlbumIdentity(
              songs,
              albumName: albumName,
              artistName: artistName,
            ),
            AlbumTracksOrigin.platform,
          );
        }
      }

      // 2) MusicBrainz：平台没有这张专辑时的权威曲目表（不可播放）。
      if (albumName.isNotEmpty) {
        final discography = ref.watch(musicBrainzDiscographyProvider);
        final tracks = await discography.tracksForRelease(
          artistName,
          albumName,
        );
        if (tracks.isNotEmpty) {
          return build(
            tracks
                .map(
                  (track) => MusicItem(
                    id: 'mb:${query.albumId}:${track.position}:${track.title}',
                    name: track.title,
                    singer: artistName,
                    album: albumName,
                    duration: track.length ?? Duration.zero,
                    source: 'musicbrainz',
                    platform: platformId,
                    isPlayable: false,
                    meta: {
                      'albumTrackOrigin': 'musicbrainz',
                      'trackPosition': track.position,
                    },
                  ),
                )
                .toList(growable: false),
            AlbumTracksOrigin.musicBrainz,
          );
        }
      }

      // 3) 兜底：搜索命中的同专辑歌曲（数量可能不全，但可播放）。
      if (albumName.isNotEmpty) {
        final queryText = artistName.isEmpty
            ? albumName
            : '$artistName $albumName';
        final hits = await service.search(
          queryText,
          customSourceId: platformId,
          limit: 50,
          type: 'music',
        );
        final matched = songsInAlbum(
          hits,
          albumName: albumName,
          artistName: artistName,
        );
        return build(matched, AlbumTracksOrigin.search);
      }

      return build(const [], AlbumTracksOrigin.search);
    });

/// 歌手页里单张专辑的完整曲目查询。
///
/// [albumId] 是平台专辑 id；[platform] 是已经解析好的平台源 id。
typedef ArtistAlbumTracksQuery = ({
  String albumId,
  String platform,
  String album,
  String artist,
});

/// 歌手页每张专辑的完整曲目：平台专辑接口优先，失败时用 MusicBrainz 曲目表。
///
/// MusicBrainz 自身串行限速并缓存结果；只有平台接口没有给出曲目时才请求，
/// 没有平台专辑 id 的分组也可以通过专辑名补齐。搜索命中列表始终由 UI 做即时回退。
///
/// 不用 autoDispose：滚动离开再回来不该重新发一次请求。
final artistAlbumTracksProvider =
    FutureProvider.family<List<MusicItem>, ArtistAlbumTracksQuery>((
      ref,
      query,
    ) async {
      final service = ref.watch(musicSourceServiceProvider);
      if (query.albumId.isNotEmpty) {
        final songs = await service.getAlbumSongs(
          query.albumId,
          sourceId: query.platform,
        );
        final artistSongs = songs
            .where((song) => songsForArtist([song], query.artist).isNotEmpty)
            .toList(growable: false);
        if (artistSongs.isNotEmpty) {
          return fillAlbumIdentity(
            artistSongs,
            albumName: query.album,
            artistName: query.artist,
          );
        }
      }

      if (query.album.trim().isEmpty || query.artist.trim().isEmpty) {
        return const [];
      }
      final discography = ref.watch(musicBrainzDiscographyProvider);
      final tracks = await discography.tracksForRelease(
        query.artist,
        query.album,
      );
      if (tracks.isEmpty) return const [];
      return tracks
          .map(
            (track) => MusicItem(
              id: 'mb:${query.albumId}:${track.position}:${track.title}',
              name: track.title,
              singer: query.artist,
              album: query.album,
              duration: track.length ?? Duration.zero,
              source: 'musicbrainz',
              platform: query.platform,
              isPlayable: false,
              meta: {
                'albumTrackOrigin': 'musicbrainz',
                'trackPosition': track.position,
              },
            ),
          )
          .toList(growable: false);
    });

/// MusicBrainz 曲目播放前的匹配：按歌名回平台搜一次，取第一个可播放结果。
///
/// 只用于 [AlbumTracksOrigin.musicBrainz] 的行；平台曲目自身有地址，
/// 不需要这一步。
Future<MusicItem?> resolveMusicBrainzTrack(
  MusicSourceService service, {
  required MusicItem track,
  required String artistName,
  required String platformId,
}) async {
  final queries = <String>[
    if (artistName.isNotEmpty) '${track.name} $artistName',
    '${track.name} ${track.album}'.trim(),
  ];
  for (final query in queries) {
    if (query.trim().isEmpty) continue;
    final hits = await service.search(
      query,
      customSourceId: platformId,
      limit: 10,
      type: 'music',
    );
    for (final hit in hits) {
      if (!hit.isPlayable) continue;
      if (_looselyMatches(hit.name, track.name)) return hit;
    }
  }
  return null;
}

bool _looselyMatches(String candidate, String wanted) {
  final left = normalizeAlbumName(candidate);
  final right = normalizeAlbumName(wanted);
  if (left.isEmpty || right.isEmpty) return false;
  return left == right || left.contains(right) || right.contains(left);
}
