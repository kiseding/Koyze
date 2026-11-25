import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/search/domain/artist_albums.dart';

MusicItem _song(String id, String album, {Map<String, dynamic>? meta}) {
  return MusicItem(
    id: id,
    name: 'song-$id',
    singer: '某歌手',
    album: album,
    source: 'tx',
    platform: 'tx',
    meta: meta,
  );
}

void main() {
  group('parseAlbumTime', () {
    test('parses year, seconds, milliseconds and ISO strings', () {
      expect(parseAlbumTime('2021'), DateTime(2021));
      expect(parseAlbumTime(2022), DateTime(2022));
      expect(
        parseAlbumTime(1609459200),
        DateTime.fromMillisecondsSinceEpoch(1609459200 * 1000),
      );
      expect(
        parseAlbumTime(1609459200000),
        DateTime.fromMillisecondsSinceEpoch(1609459200000),
      );
      expect(parseAlbumTime('2019-08-03'), DateTime(2019, 8, 3));
      expect(parseAlbumTime('not a date'), isNull);
      expect(parseAlbumTime(42), isNull);
    });
  });

  group('groupSongsByAlbum', () {
    test('groups same album and sorts albums by newest time first', () {
      final groups = groupSongsByAlbum([
        _song('1', '旧专辑', meta: {'year': '2018'}),
        _song('2', '新专辑', meta: {'publishTime': 1609459200000}),
        _song('3', '旧专辑', meta: {'year': '2018'}),
        _song('4', '中专辑', meta: {'year': 2020}),
      ]);

      expect(groups.map((group) => group.name), ['新专辑', '中专辑', '旧专辑']);
      expect(groups.first.songs.map((song) => song.id), ['2']);
      expect(groups.last.songs.map((song) => song.id), ['1', '3']);
    });

    test('albums without time keep source order after timed albums', () {
      final groups = groupSongsByAlbum([
        _song('1', '未知时间A'),
        _song('2', '有发行时间', meta: {'releaseDate': '2017-05-01'}),
        _song('3', '未知时间B'),
      ]);

      expect(groups.map((group) => group.name), ['有发行时间', '未知时间A', '未知时间B']);
    });

    test('uses newest time inside an album and keeps in-album order', () {
      final groups = groupSongsByAlbum([
        _song('1', '精选', meta: {'year': 2010}),
        _song('2', '精选', meta: {'year': 2023}),
        _song('3', '精选', meta: {'year': 2015}),
      ]);

      expect(groups.single.time, DateTime(2023));
      expect(groups.single.songs.map((song) => song.id), ['1', '2', '3']);
    });

    test('reads nested album metadata', () {
      final groups = groupSongsByAlbum([
        _song(
          '1',
          '嵌套',
          meta: {
            'al': {'publishTime': '2024-02-01'},
          },
        ),
      ]);

      expect(groups.single.time, DateTime(2024, 2, 1));
    });
  });
}
