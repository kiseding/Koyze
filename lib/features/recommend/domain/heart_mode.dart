import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../player/domain/music_item.dart';

/// 搜索入口的签名。抽成 typedef 是为了让 [HeartModeService] 能脱离网络单测。
typedef HeartSearch =
    Future<List<MusicItem>> Function(String keyword, {int limit});

/// 「心动模式」：围绕当前这首歌，生成一批接着能听的歌。
///
/// 这里刻意不猜"你可能喜欢什么"——那是推荐引擎的事（`recommendation_engine`
/// 已经用收藏做了画像）。心动模式要解决的是更小的一个场景：**当前这首放完，
/// 下一首放什么不突兀**。所以它只用三条现成的线索，按可信度排序：
///
/// 1. 同一位歌手（最稳，用户点了心动就是想多听这个人的）；
/// 2. 同一张专辑（次稳，专辑内曲目风格一致）；
/// 3. 歌手 + 热门（补量，避免小众歌手只有两三首）。
///
/// 结果会按「同歌手 > 同专辑 > 其它」分层、层内随机，这样连续两次点心动
/// 顺序不同，但都不会把不相关的歌排到同歌手前面。
class HeartModeService {
  HeartModeService({required HeartSearch search, Random? random})
    : this._(search, random ?? Random());

  HeartModeService._(this._search, this._random);

  final HeartSearch _search;
  final Random _random;

  /// 生成一批可接续播放的歌曲（不含 [seed] 自己）。
  ///
  /// [exclude] 用来剔除已经在队列里的歌，避免心动模式把队列变成复读。
  Future<List<MusicItem>> buildRadio(
    MusicItem seed, {
    int size = 40,
    Set<String> exclude = const {},
  }) async {
    final seen = <String>{seed.identityKey, ...exclude};
    final sameArtist = <MusicItem>[];
    final sameAlbum = <MusicItem>[];
    final others = <MusicItem>[];

    Future<void> collect(String keyword, int limit) async {
      if (keyword.trim().isEmpty) return;
      List<MusicItem> results;
      try {
        results = await _search(keyword, limit: limit);
      } catch (error) {
        debugPrint('[HeartMode] 搜索 "$keyword" 失败: $error');
        return;
      }
      for (final item in results) {
        if (!seen.add(item.identityKey)) continue;
        if (_isSameArtist(item, seed)) {
          sameArtist.add(item);
        } else if (_isSameAlbum(item, seed)) {
          sameAlbum.add(item);
        } else {
          others.add(item);
        }
      }
    }

    final artist = seed.singer.trim();
    final album = seed.album.trim();
    await collect(artist, size * 2);
    // 同歌手不够时再补专辑与热门：串行请求，命中足够就不再多打一次。
    if (sameArtist.length < size && album.isNotEmpty) {
      await collect(album, size);
    }
    if (sameArtist.length + sameAlbum.length < size && artist.isNotEmpty) {
      await collect('$artist 热门', size);
    }

    sameArtist.shuffle(_random);
    sameAlbum.shuffle(_random);
    others.shuffle(_random);

    final ordered = [...sameArtist, ...sameAlbum, ...others];
    if (ordered.length > size) return ordered.sublist(0, size);
    return ordered;
  }

  static bool _isSameArtist(MusicItem a, MusicItem b) {
    final left = a.singer.trim();
    final right = b.singer.trim();
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    // 合唱曲目写成 "A/B"、"A、B"，只要有一个名字重合就算同歌手。
    final leftNames = _splitArtists(left);
    final rightNames = _splitArtists(right);
    return leftNames.any(rightNames.contains);
  }

  static bool _isSameAlbum(MusicItem a, MusicItem b) {
    final left = a.album.trim();
    final right = b.album.trim();
    return left.isNotEmpty && left == right;
  }

  static Set<String> _splitArtists(String value) {
    return value
        .split(RegExp(r'[/、,&]'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
  }
}
