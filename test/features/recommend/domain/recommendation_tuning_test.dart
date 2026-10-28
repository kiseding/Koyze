import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/recommend/domain/recommendation_tuning.dart';

MusicItem track(String name, String singer) => MusicItem(
  id: '$name-$singer',
  name: name,
  singer: singer,
  duration: Duration.zero,
  source: 'src',
  platform: 'tx',
);

void main() {
  test('空调校什么都不挡', () {
    const tuning = RecommendationTuning.empty;
    expect(tuning.isEmpty, isTrue);
    expect(tuning.allows(track('晴天', '周杰伦')), isTrue);
    expect(tuning.toJson(), isEmpty);
  });

  test('屏蔽歌手按包含关系生效，屏蔽歌曲按歌名 + 歌手', () {
    final tuning = RecommendationTuning.empty
        .withExcludedArtists(['周杰伦'])
        .withExcludedSongs([const SongRef(title: '晴天', artist: '周杰伦')]);

    // 同一歌手的其他歌也被挡掉。
    expect(tuning.allows(track('夜曲', '周杰伦')), isFalse);
    expect(tuning.allows(track('晴天', '周杰伦')), isFalse);
    // 别的歌手不受影响。
    expect(tuning.allows(track('晴天', '孙燕姿')), isTrue);
    expect(tuning.allows(track('后来', '刘若英')), isTrue);
  });

  test('只给歌名也能屏蔽，标点与大小写不影响匹配', () {
    final tuning = RecommendationTuning.empty.withExcludedSongs([
      const SongRef(title: 'Shape of You'),
    ]);
    expect(tuning.allows(track('shape of you', 'Ed Sheeran')), isFalse);
    expect(tuning.allows(track('Shape Of You (Live)', 'Ed Sheeran')), isFalse);
    expect(tuning.allows(track('Perfect', 'Ed Sheeran')), isTrue);
  });

  test('置顶去重并保留顺序，超过上限截断', () {
    final refs = [
      for (var i = 0; i < RecommendationTuning.maxPinned + 5; i++)
        SongRef(title: '歌$i', artist: '歌手'),
      const SongRef(title: '歌0', artist: '歌手'),
    ];
    final tuning = RecommendationTuning.empty.withPinned(refs);
    expect(tuning.pinned.length, RecommendationTuning.maxPinned);
    expect(tuning.pinned.first.title, '歌0');
    expect(tuning.isPinned(track('歌0', '歌手')), isTrue);
    expect(tuning.isPinned(track('歌0', '别人')), isFalse);
  });

  test('口味提示去掉首尾空白，过长截断', () {
    final tuning = RecommendationTuning.empty.withFocus('  多来点粤语老歌  ');
    expect(tuning.focus, '多来点粤语老歌');

    final long = RecommendationTuning.empty.withFocus('啊' * 500);
    expect(long.focus.length, RecommendationTuning.maxFocusLength);
  });

  test('clear 可以只清一类，也可以全清', () {
    final tuning = RecommendationTuning.empty
        .withPinned([const SongRef(title: '晴天')])
        .withExcludedSongs([const SongRef(title: '夜曲')])
        .withExcludedArtists(['周杰伦'])
        .withFocus('太吵的不要');

    final onlyFocusCleared = tuning.cleared({TuningSection.focus});
    expect(onlyFocusCleared.focus, isEmpty);
    expect(onlyFocusCleared.pinned, isNotEmpty);
    expect(onlyFocusCleared.excludedArtists, isNotEmpty);

    final all = tuning.cleared({TuningSection.all});
    expect(all.isEmpty, isTrue);
  });

  test('JSON 往返，坏数据被忽略而不是整份丢掉', () {
    final tuning = RecommendationTuning.empty
        .withPinned([const SongRef(title: '晴天', artist: '周杰伦')])
        .withExcludedArtists(['某人'])
        .withFocus('多来点摇滚');
    final restored = RecommendationTuning.fromJson(tuning.toJson());
    expect(restored.pinned.single.title, '晴天');
    expect(restored.pinned.single.artist, '周杰伦');
    expect(restored.excludedArtists, ['某人']);
    expect(restored.focus, '多来点摇滚');

    final messy = RecommendationTuning.fromJson({
      'pinned': ['夜曲', 42, {'title': ''}, {'name': '稻香', 'singer': '周杰伦'}],
      'excludedSongs': 'not a list',
      'excludedArtists': [1, '  ', '周杰伦'],
      'focus': 123,
    });
    expect(messy.pinned.map((ref) => ref.title), ['夜曲', '稻香']);
    expect(messy.excludedSongs, isEmpty);
    expect(messy.excludedArtists, ['1', '周杰伦']);
    expect(messy.focus, '123');
  });

  test('describe 用一句话说清楚改了什么', () {
    final tuning = RecommendationTuning.empty
        .withPinned([const SongRef(title: '晴天')])
        .withExcludedSongs([const SongRef(title: '夜曲')])
        .withExcludedArtists(['某人'])
        .withFocus('多来点摇滚');
    expect(tuning.describe(), '置顶 1 首 · 屏蔽 1 首 · 屏蔽 1 位歌手 · 口味「多来点摇滚」');
  });
}
