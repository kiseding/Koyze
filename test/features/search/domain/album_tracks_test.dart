import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/search/domain/album_tracks.dart';

MusicItem _song({
  required String name,
  required String singer,
  required String album,
  String platform = 'tx',
  Map<String, dynamic>? meta,
  bool playable = true,
}) => MusicItem(
  id: name,
  name: name,
  singer: singer,
  album: album,
  source: platform,
  platform: platform,
  isPlayable: playable,
  meta: meta,
);

void main() {
  group('albumIdOf', () {
    test('reads QQ albummid and drops the placeholder value', () {
      expect(
        albumIdOf(
          _song(
            name: 'a',
            singer: 's',
            album: 'x',
            meta: {'albummid': '000MkMni19ClKG'},
          ),
        ),
        '000MkMni19ClKG',
      );
      expect(
        albumIdOf(
          _song(name: 'a', singer: 's', album: 'x', meta: {'albummid': '空'}),
        ),
        '',
      );
    });

    test('reads the NetEase nested album id', () {
      expect(
        albumIdOf(
          _song(
            name: 'a',
            singer: 's',
            album: 'x',
            platform: 'wy',
            meta: {
              'al': {'id': 372081313, 'name': '叶惠美'},
            },
          ),
        ),
        '372081313',
      );
    });

    test('reads KuGou AlbumID and album_id', () {
      expect(
        albumIdOf(
          _song(
            name: 'a',
            singer: 's',
            album: 'x',
            platform: 'kg',
            meta: {'AlbumID': 966846},
          ),
        ),
        '966846',
      );
      expect(
        albumIdOf(
          _song(
            name: 'a',
            singer: 's',
            album: 'x',
            platform: 'kg',
            meta: {'album_id': '966846'},
          ),
        ),
        '966846',
      );
    });

    test('reads Kuwo ALBUMID', () {
      expect(
        albumIdOf(
          _song(
            name: 'a',
            singer: 's',
            album: '叶惠美',
            platform: 'kw',
            meta: {'ALBUMID': '1293'},
          ),
        ),
        '1293',
      );
    });

    test('returns empty for platforms without an album id', () {
      expect(
        albumIdOf(
          _song(
            name: 'a',
            singer: 's',
            album: 'x',
            platform: 'local',
            meta: {'path': '/a.mp3'},
          ),
        ),
        '',
      );
      expect(albumIdOf(_song(name: 'a', singer: 's', album: 'x')), '');
    });
  });

  group('fillAlbumIdentity', () {
    test(
      'fills missing album and unknown singer without touching known ones',
      () {
        final result = fillAlbumIdentity(
          [
            _song(name: 'a', singer: '未知歌手', album: ''),
            _song(name: 'b', singer: '周杰伦', album: '叶惠美'),
          ],
          albumName: '叶惠美',
          artistName: '周杰伦',
        );

        expect(result[0].album, '叶惠美');
        expect(result[0].singer, '周杰伦');
        expect(result[1].singer, '周杰伦');
      },
    );
  });

  group('songsInAlbum', () {
    test('keeps only playable tracks of the same album and artist', () {
      final songs = [
        _song(name: 'a', singer: '周杰伦', album: '叶惠美'),
        _song(name: 'b', singer: '周杰伦', album: '叶惠美 (Live)'),
        _song(name: 'c', singer: '别人', album: '叶惠美'),
        _song(name: 'd', singer: '周杰伦', album: '叶惠美', playable: false),
      ];

      final matched = songsInAlbum(songs, albumName: '叶惠美', artistName: '周杰伦');
      expect(matched.map((song) => song.name), ['a']);
    });

    test('ignores punctuation differences in the album name', () {
      final matched = songsInAlbum(
        [_song(name: 'a', singer: 's', album: 'Sgt. Pepper’s')],
        albumName: 'Sgt Pepper’s',
        artistName: '',
      );
      expect(matched, hasLength(1));
    });

    test('returns empty when the album name is blank', () {
      expect(
        songsInAlbum(
          [_song(name: 'a', singer: 's', album: '')],
          albumName: '   ',
          artistName: 's',
        ),
        isEmpty,
      );
    });
  });
}
