import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/search/domain/local_song_search.dart';

MusicItem _song(String name, String singer, {String album = '范特西'}) {
  return MusicItem(
    id: '$name-$singer',
    name: name,
    singer: singer,
    album: album,
    source: 'local',
    platform: 'local',
  );
}

void main() {
  final library = [
    _song('晴天', '周杰伦'),
    _song('七里香', '周杰伦'),
    _song('稻香', '周杰伦'),
    _song('晴天 (Live)', '周杰伦'),
    _song('Lemon', '米津玄師', album: 'BOOTLEG'),
    _song('夜曲', '周杰伦'),
  ];

  late LocalSongSearchIndex index;

  setUpAll(() {
    index = LocalSongSearchIndex.fromSongs(library);
  });

  group('拼音检索', () {
    test('首字母能命中中文歌名和歌手', () {
      final hits = index.search('zjl');
      expect(hits, isNotEmpty);
      expect(
        hits.every((hit) => hit.song.singer == '周杰伦'),
        isTrue,
        reason: 'zjl 只应命中周杰伦名下的歌',
      );
    });

    test('全拼能命中', () {
      final names = index.search('zhoujielun').map((hit) => hit.song.name);
      expect(names, containsAll(<String>['晴天', '七里香', '稻香']));
    });

    test('歌名全拼可以单独命中', () {
      final hits = index.search('qingtian');
      expect(hits.first.song.name, '晴天');
    });

    test('拼音命中的排在字面命中之后', () {
      final hits = index.search('qing');
      expect(hits.first.song.name, '晴天');
    });

    test('全角输入按半角处理', () {
      expect(index.search('ＺＪＬ'), isNotEmpty);
    });
  });

  group('排序', () {
    test('完全同名的短标题排在带后缀的前面', () {
      final hits = index.search('晴天');
      expect(hits.first.song.name, '晴天');
      expect(hits.map((hit) => hit.song.name), contains('晴天 (Live)'));
    });

    test('整串命中优先于分词命中', () {
      final hits = index.search('晴天');
      expect(hits.first.type, LocalSongMatchType.exact);
    });

    test('多个词是「与」关系，两个都要命中', () {
      final hits = index.search('周杰伦 稻香');
      expect(hits, hasLength(1));
      expect(hits.single.song.name, '稻香');
    });

    test('专辑也参与字面匹配', () {
      final hits = index.search('范特西');
      expect(hits.length, 5);
    });
  });

  group('边界', () {
    test('空查询返回空结果', () {
      expect(index.search('   '), isEmpty);
    });

    test('无匹配返回空结果', () {
      expect(index.search('不存在的歌名'), isEmpty);
    });

    test('单字母不做拼音匹配，避免把整个曲库倒出来', () {
      expect(index.search('a'), isEmpty);
    });

    test('limit 截断排序后的结果', () {
      final hits = index.search('周杰伦', limit: 2);
      expect(hits, hasLength(2));
    });

    test('模糊子序列能命中英文标题', () {
      final hits = index.search('lmn');
      expect(hits.first.song.name, 'Lemon');
    });
  });

  group('索引缓存', () {
    test('曲库超过阈值时在 isolate 里构建，结果与同步构建一致', () async {
      final songs = [
        for (var i = 0; i < LocalSongSearchIndex.isolateThreshold + 10; i++)
          MusicItem(
            id: 'id$i',
            name: '歌曲$i',
            singer: '歌手$i',
            album: '专辑',
            source: 'local',
            platform: 'local',
          ),
      ];

      final index = await LocalSongSearchIndex.build(songs);
      expect(index.length, songs.length);
      expect(index.search('歌曲7').first.song.id, 'id7');
      expect(index.search('gq7'), isNotEmpty);
    });
    test('同一批歌复用同一份索引', () async {
      final cache = LocalSongSearchCache();
      final first = await cache.indexFor(library);
      final second = await cache.indexFor(library);
      expect(identical(first, second), isTrue);
    });

    test('歌名变化后指纹变化并重建', () async {
      final cache = LocalSongSearchCache();
      final before = await cache.indexFor(library);
      final renamed = [
        _song('晴天', '周杰伦'),
        _song('七里香 (Remaster)', '周杰伦'),
        ...library.skip(2),
      ];
      final after = await cache.indexFor(renamed);
      expect(identical(before, after), isFalse);
      expect(LocalSongSearchCache.fingerprint(renamed), isNot(
        LocalSongSearchCache.fingerprint(library),
      ));
    });

    test('并发请求共用一次构建', () async {
      final cache = LocalSongSearchCache();
      final results = await Future.wait([
        cache.indexFor(library),
        cache.indexFor(library),
      ]);
      expect(identical(results.first, results.last), isTrue);
    });
  });
}
