import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/network/music_source_service.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/domain/ai_playlist_planner.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/player/domain/music_item.dart';

void main() {
  group('parse', () {
    test('reads the documented shape', () {
      final draft = AiPlaylistPlanner.parse(
        '{"name":"深夜","description":"安静一点",'
        '"songs":[{"title":"晴天","artist":"周杰伦","reason":"经典"}]}',
      );

      expect(draft.name, equals('深夜'));
      expect(draft.description, equals('安静一点'));
      expect(draft.songs, hasLength(1));
      expect(draft.songs.first.title, equals('晴天'));
      expect(draft.songs.first.artist, equals('周杰伦'));
      expect(draft.songs.first.query, equals('晴天 周杰伦'));
    });

    test('survives a markdown fence and chattering around the JSON', () {
      final draft = AiPlaylistPlanner.parse(
        '好的，这是歌单：\n```json\n{"name":"通勤",'
        '"songs":["夜曲",{"name":"稻香","singer":"周杰伦"}]}\n```\n希望你喜欢！',
      );

      expect(draft.name, equals('通勤'));
      expect(
        draft.songs.map((song) => song.title),
        equals(['夜曲', '稻香']),
      );
      expect(draft.songs.last.artist, equals('周杰伦'));
    });

    test('accepts the alias keys a model might pick', () {
      final draft = AiPlaylistPlanner.parse(
        '{"title":"别名","desc":"说明","tracks":[{"song":"七里香"}]}',
      );

      expect(draft.name, equals('别名'));
      expect(draft.description, equals('说明'));
      expect(draft.songs.single.title, equals('七里香'));
    });

    test('drops entries without a title and caps the length', () {
      final songs = List.generate(
        40,
        (index) => index == 0 ? '{"artist":"x"}' : '{"title":"歌$index"}',
      ).join(',');
      final draft = AiPlaylistPlanner.parse('{"name":"n","songs":[$songs]}');

      expect(draft.songs, hasLength(AiPlaylistPlanner.maxSongs));
      expect(draft.songs.first.title, equals('歌1'));
    });

    test('falls back to the request text as the playlist name', () {
      final draft = AiPlaylistPlanner.parse(
        '{"songs":[]}',
        fallbackName: '  适合写代码时听的纯音乐，不要太吵，也不要有人声  ',
      );

      expect(draft.songs, isEmpty);
      expect(draft.isEmpty, isTrue);
      expect(draft.name, startsWith('适合写代码时听的纯音乐'));
      expect(draft.name, endsWith('…'));
      expect(draft.name.length, lessThanOrEqualTo(21));
    });

    test('rejects an answer with no JSON at all', () {
      expect(
        () => AiPlaylistPlanner.parse('抱歉，我无法完成这个请求。'),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiFailureKind.badResponse,
          ),
        ),
      );
    });

    test('rejects a malformed payload between braces', () {
      expect(
        () => AiPlaylistPlanner.parse('{"name": "x",,}'),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiFailureKind.badResponse,
          ),
        ),
      );
      expect(
        () => AiPlaylistPlanner.parse('[1,2,3]'),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('scoreOf', () {
    AiSongRequest want(String title, [String artist = '']) =>
        AiSongRequest(title: title, artist: artist);

    test('exact title with the right artist is a perfect score', () {
      expect(
        AiPlaylistMatcher.scoreOf(want('晴天', '周杰伦'), have('晴天', '周杰伦')),
        equals(1),
      );
    });

    test('exact title without an artist hint stays high but not perfect', () {
      expect(
        AiPlaylistMatcher.scoreOf(want('晴天'), have('晴天', '周杰伦')),
        equals(0.9),
      );
      expect(
        AiPlaylistMatcher.scoreOf(want('晴天', '陈奕迅'), have('晴天', '周杰伦')),
        equals(0.8),
      );
    });

    test('a versioned title still matches, weaker', () {
      expect(
        AiPlaylistMatcher.scoreOf(
          want('晴天', '周杰伦'),
          have('晴天 (Live)', '周杰伦'),
        ),
        equals(0.7),
      );
      expect(
        AiPlaylistMatcher.scoreOf(
          want('晴天', '陈奕迅'),
          have('晴天 (Live)', '周杰伦'),
        ),
        equals(0.55),
      );
      // 0.55 正好达到门槛，能被采纳。
      expect(AiPlaylistMatcher.minimumScore, equals(0.55));
    });

    test('punctuation and spacing do not get in the way', () {
      expect(
        AiPlaylistMatcher.scoreOf(
          want('七里香', '周杰伦'),
          have('七里-香', '周杰伦'),
        ),
        equals(1),
      );
    });

    test('a different song scores zero', () {
      expect(
        AiPlaylistMatcher.scoreOf(want('晴天', '周杰伦'), have('稻香', '周杰伦')),
        equals(0),
      );
      expect(AiPlaylistMatcher.scoreOf(want('  '), have('稻香', '周杰伦')), equals(0));
    });
  });

  group('match', () {
    test('keeps only the closest version and reports progress', () async {
      final service = _FakeMusicSource({
        '晴天 周杰伦': [
          have('晴天', '周杰伦'),
          have('晴天 (Live)', '周杰伦'),
        ],
        '不存在的歌': [have('另一首', '别人')],
      });
      final progress = <String>[];

      final matches = await AiPlaylistMatcher(service: service).match(
        [
          const AiSongRequest(title: '晴天', artist: '周杰伦'),
          const AiSongRequest(title: '不存在的歌'),
        ],
        onProgress: (done, total) => progress.add('$done/$total'),
      );

      expect(matches, hasLength(2));
      expect(matches.first.matched, isTrue);
      expect(matches.first.song!.name, equals('晴天'));
      expect(matches.last.matched, isFalse);
      expect(progress, equals(['0/2', '1/2', '2/2']));
    });

    test('a search failure only blanks that one song', () async {
      final service = _FakeMusicSource({
        '晴天 周杰伦': [have('晴天', '周杰伦')],
      }, failing: {'坏查询'});

      final matches = await AiPlaylistMatcher(service: service).match([
        const AiSongRequest(title: '坏查询'),
        const AiSongRequest(title: '晴天', artist: '周杰伦'),
      ]);

      expect(matches.first.matched, isFalse);
      expect(matches[1].matched, isTrue);
    });

    test('cancelling stops before the next song', () async {
      final service = _FakeMusicSource({});
      var seen = 0;

      final matches = await AiPlaylistMatcher(service: service).match(
        [
          const AiSongRequest(title: 'a'),
          const AiSongRequest(title: 'b'),
        ],
        isCancelled: () => seen++ > 0,
      );

      expect(matches, hasLength(1));
    });
  });
}

MusicItem have(String name, String singer) =>
    MusicItem(id: name, name: name, singer: singer, source: 'kw');

class _FakeMusicSource extends MusicSourceService {
  _FakeMusicSource(
    this.catalog, {
    this.failing = const <String>{},
  }) : super(_NoopCustomSourceService());

  final Map<String, List<MusicItem>> catalog;
  final Set<String> failing;

  @override
  Future<List<MusicItem>> search(
    String keyword, {
    String? customSourceId,
    int page = 1,
    int limit = 20,
    String type = 'music',
  }) async {
    if (failing.contains(keyword)) throw Exception('search down');
    return catalog[keyword] ?? const <MusicItem>[];
  }
}

class _NoopCustomSourceService extends CustomSourceService {
  @override
  Future<void> init() async {}
}
