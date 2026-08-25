import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/recommend/domain/recommendation_engine.dart';

MusicItem _song(
  String id,
  String name,
  String singer,
  String album, {
  String platform = 'tx',
}) {
  return MusicItem(
    id: id,
    name: name,
    singer: singer,
    album: album,
    duration: const Duration(seconds: 200),
    source: 'x',
    platform: platform,
  );
}

void main() {
  final favorites = List.generate(
    100,
    (index) => _song('f$index', '收藏歌曲 $index', '周杰伦', '收藏专辑 ${index % 5}'),
  );

  final candidates = [
    _song('c1', '稻香', '周杰伦', '魔杰座'),
    _song('c2', '说谎', '林宥嘉', '感官世界'),
    _song('c3', '夜曲', '周杰伦', '十一月的萧邦'), // 与收藏同 id → 应被排除
  ];

  test('requires 100 favorites and caps at 30 results', () {
    final engine = const RecommendationEngine();
    final enoughCandidates = List.generate(
      30,
      (index) => _song('c$index', '候选歌曲 $index', '周杰伦', '候选专辑'),
    );
    final recs = engine.recommend(
      favorites: favorites,
      candidates: enoughCandidates,
      random: Random(1),
    );

    expect(recs, hasLength(30));
    expect(recs.every((rec) => rec.song.singer == '周杰伦'), isTrue);
    // 收藏不足 100 首时不生成推荐
    expect(
      engine.recommend(
        favorites: favorites.take(99).toList(),
        candidates: enoughCandidates,
        random: Random(1),
      ),
      isEmpty,
    );
    // 候选不足 30 首时返回已有结果，而非空
    final partial = engine.recommend(
      favorites: favorites,
      candidates: candidates,
      random: Random(1),
    );
    expect(partial, isNotEmpty);
    expect(partial.length, lessThanOrEqualTo(candidates.length));
  });

  test('returns empty when favorites are below the sample threshold', () {
    final engine = const RecommendationEngine();
    final recs = engine.recommend(favorites: const [], candidates: candidates);
    expect(recs, isEmpty);
  });

  test(
    'returns empty instead of already favored songs when all candidates are favored',
    () {
      final engine = const RecommendationEngine();
      final recs = engine.recommend(
        favorites: favorites,
        candidates: favorites,
        random: Random(1),
      );

      expect(recs, isEmpty);
    },
  );

  test('never recommends an already favored song', () {
    final engine = const RecommendationEngine();
    // 候选与收藏同 id、或仅同名同歌手（跨平台同一首歌）都必须被排除。
    final candidates = [
      _song('f0', '收藏歌曲 0', '周杰伦', '收藏专辑 0'), // 同 id
      _song('other', '收藏歌曲 5', '周杰伦', '不同专辑'), // 同 id
      _song('c1', '收藏歌曲 1', '周杰伦', '收藏专辑 1', platform: 'kw'), // 同名同歌手跨平台
      _song('c2', '稻香', '周杰伦', '魔杰座'),
    ];
    final recs = engine.recommend(
      favorites: favorites,
      candidates: candidates,
      random: Random(1),
    );

    expect(recs.map((r) => r.song.name), isNot(contains('收藏歌曲')));
    expect(recs, isNotEmpty);
    expect(recs.single.song.name, '稻香');
  });

  test('predict rewards artist affinity over platform affinity', () {
    final engine = const RecommendationEngine();
    final profile = engine.buildProfile(favorites);

    final sameArtist = _song('x1', '轨迹', '周杰伦', '其它');
    final samePlatformOnly = _song('x2', '轨迹', '林宥嘉', '其它', platform: 'tx');

    final a = engine.predict(candidate: sameArtist, profile: profile);
    final b = engine.predict(candidate: samePlatformOnly, profile: profile);
    expect(a, greaterThan(b));
  });

  test('limits one artist when multiple artists have candidates', () {
    final engine = const RecommendationEngine();
    final candidates = [
      for (var i = 0; i < 12; i++) _song('jay-$i', 'Jay $i', '周杰伦', 'Album'),
      for (var i = 0; i < 6; i++) _song('lin-$i', 'Lin $i', '林宥嘉', 'Album'),
      for (var i = 0; i < 6; i++) _song('a-mei-$i', 'A Mei $i', '张惠妹', 'Album'),
    ];

    final recs = engine.recommend(
      favorites: favorites,
      candidates: candidates,
      random: Random(1),
    );

    final counts = <String, int>{};
    for (final rec in recs) {
      counts[rec.song.singer] = (counts[rec.song.singer] ?? 0) + 1;
    }
    expect(recs, hasLength(candidates.length));
    expect(counts['周杰伦'], 12);
    expect(counts['林宥嘉'], 6);
    expect(counts['张惠妹'], 6);
  });

  test('fills 30 results while balancing artists with enough candidates', () {
    final engine = const RecommendationEngine();
    final candidates = [
      for (var artist = 0; artist < 6; artist++)
        for (var song = 0; song < 8; song++)
          _song(
            'artist-$artist-$song',
            'Song $artist-$song',
            artist == 0 ? '周杰伦' : '歌手 $artist',
            'Album',
          ),
    ];

    final recs = engine.recommend(
      favorites: favorites,
      candidates: candidates,
      random: Random(1),
    );

    expect(recs, hasLength(30));
    final counts = <String, int>{};
    for (final rec in recs) {
      counts[rec.song.singer] = (counts[rec.song.singer] ?? 0) + 1;
    }
    final values = counts.values.toList();
    expect(values.reduce(max) - values.reduce(min), lessThanOrEqualTo(1));
  });
}
