import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/nas/domain/nas_library_groups.dart';
import 'package:koyze/features/player/domain/music_item.dart';

MusicItem _song(
  String name, {
  String singer = '',
  String album = '',
  String? artwork,
  String? folder,
}) {
  return MusicItem(
    id: 'webdav://$name',
    name: name,
    singer: singer,
    album: album,
    source: 'webdav',
    platform: 'webdav',
    artwork: artwork,
    meta: {if (folder != null) 'folder': folder},
  );
}

void main() {
  group('groupNasSongs', () {
    test('groups albums by name and artist and keeps the first artwork', () {
      final collections = groupNasSongs(
        [
          _song('a', singer: '周杰伦', album: '范特西'),
          _song(
            'b',
            singer: '周杰伦',
            album: '范特西',
            artwork: 'http://nas/cover.jpg',
          ),
          _song('c', singer: '五月天', album: '自传'),
        ],
        NasGrouping.album,
        unknownAlbum: '未知专辑',
      );

      expect(collections, hasLength(2));
      final fantasy = collections.firstWhere((item) => item.title == '范特西');
      expect(fantasy.songs, hasLength(2));
      expect(fantasy.subtitle, '周杰伦');
      expect(fantasy.artwork, 'http://nas/cover.jpg');
    });

    test('does not merge same-name albums from different artists', () {
      final collections = groupNasSongs(
        [
          _song('a', singer: 'A', album: '同名专辑'),
          _song('b', singer: 'B', album: '同名专辑'),
        ],
        NasGrouping.album,
        unknownAlbum: '未知专辑',
      );

      expect(collections, hasLength(2));
    });

    test('falls back to the unknown labels', () {
      final albums = groupNasSongs(
        [_song('a')],
        NasGrouping.album,
        unknownAlbum: '未知专辑',
      );
      final artists = groupNasSongs(
        [_song('a')],
        NasGrouping.artist,
        unknownArtist: '未知艺术家',
      );

      expect(albums.single.title, '未知专辑');
      expect(artists.single.title, '未知艺术家');
    });

    test('groups folders by the stored path and titles them by last segment',
        () {
      final collections = groupNasSongs(
        [
          _song('a', folder: '周杰伦/范特西'),
          _song('b', folder: '周杰伦/范特西'),
          _song('c', folder: '五月天/自传'),
          _song('d'),
        ],
        NasGrouping.folder,
      );

      expect(collections, hasLength(3));
      final fantasy = collections.firstWhere((item) => item.title == '范特西');
      expect(fantasy.songs, hasLength(2));
      expect(fantasy.subtitle, '周杰伦/范特西');
      expect(collections.map((item) => item.title), contains('/'));
    });
  });
}
