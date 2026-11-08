import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/music_source/platform/wy_source.dart';
import '../../player/domain/music_item.dart';
import '../domain/song_comment.dart';

/// 歌曲信息用到的网易实例。
///
/// 独立构造而不是从 `MusicSourceService` 里掏：那边只暴露「按平台取歌词/封面」
/// 这类统一接口，评论与相似歌曲是网易独有的能力，硬塞进通用接口反而会把
/// 其他平台的实现撑成一堆 `return null`。
final songInfoSourceProvider = Provider<WySource>((ref) => WySource());

/// 这首歌的网易 id。非网易曲目返回 null（其他平台没有对应接口）。
String? neteaseIdOf(MusicItem music) {
  final platform = music.platform.isNotEmpty ? music.platform : music.source;
  if (platform != 'wy') return null;
  final id = music.songmid?.trim() ?? '';
  return id.isNotEmpty ? id : music.id;
}

final songCommentsProvider =
    FutureProvider.autoDispose.family<SongCommentsPage?, String>((
      ref,
      songId,
    ) async {
      return ref.watch(songInfoSourceProvider).fetchComments(songId);
    });

final similarSongsProvider =
    FutureProvider.autoDispose.family<List<MusicItem>, String>((
      ref,
      songId,
    ) async {
      return ref.watch(songInfoSourceProvider).fetchSimilarSongs(songId);
    });
