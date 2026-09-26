import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/domain/playlist_import_service.dart';

void main() {
  test('QQ playlist import preserves media_mid for playback URL lookup', () {
    expect(
      PlaylistImportService.txMediaMid({'strMediaMid': 'preferred'}),
      'preferred',
    );
    expect(
      PlaylistImportService.txMediaMid({
        'file': {'media_mid': 'legacy'},
      }),
      'legacy',
    );
    expect(PlaylistImportService.txMediaMid({}), isEmpty);
  });

  test('Kuwo playlist import resolves short album artwork fields', () {
    expect(
      PlaylistImportService.kwArtwork({
        'web_albumpic_short': '120/abc/def.jpg',
      }),
      'https://img1.kuwo.cn/star/albumcover/500/abc/def.jpg',
    );
    expect(
      PlaylistImportService.kwArtwork({
        'web_artistpic_short': '120/artist.jpg',
      }),
      'https://img1.kuwo.cn/star/starheads/500/artist.jpg',
    );
  });

  test('NetEase endpoints follow the Netease_url two step method', () {
    expect(
      PlaylistImportService.wyPlaylistDetailUrl,
      'https://music.163.com/api/v6/playlist/detail',
    );
    expect(
      PlaylistImportService.wySongDetailUrl,
      'https://interface3.music.163.com/api/v3/song/detail',
    );
    expect(PlaylistImportService.wySongDetailBatchSize, 100);
  });

  test('NetEase trackIds keep playlist order and duplicated copies', () {
    final ids = PlaylistImportService.wyTrackIds({
      'trackIds': [
        {'id': 3},
        {'id': 1},
        {'id': 3},
      ],
      // trackIds 存在时必须优先使用，tracks 只是前若干首的截断副本。
      'tracks': [
        {'id': 999},
      ],
    });
    expect(ids, ['3', '1', '3']);
  });

  test('NetEase trackIds fall back to tracks when trackIds is missing', () {
    final ids = PlaylistImportService.wyTrackIds({
      'tracks': [
        {'id': 11},
        {'id': '22'},
        {'id': 'not-an-id'},
      ],
    });
    expect(ids, ['11', '22']);
  });

  test('NetEase song detail merges privileges by song id', () {
    final details = PlaylistImportService.wyDecodeSongDetail({
      'code': 200,
      'songs': [
        {
          'id': 7,
          'name': '曲目',
          'ar': [
            {'name': '甲'},
            {'name': '乙'},
          ],
          'al': {'name': '专辑', 'picUrl': 'http://p1.music.126.net/x.jpg'},
          'dt': 196000,
        },
      ],
      'privileges': [
        {'id': 7, 'maxbr': 999000, 'pl': 320000},
      ],
    });

    expect(details.keys.toList(), ['7']);
    expect(details['7']!['privilege'], {
      'id': 7,
      'maxbr': 999000,
      'pl': 320000,
    });
  });

  test('NetEase import assembles songs in order and skips missing details', () {
    final songs = PlaylistImportService.wySongsFromDetails(
      ['1', '2', '1', '404'],
      {
        '1': {
          'id': 1,
          'name': 'A',
          'ar': [
            {'name': '甲'},
          ],
          'al': {'name': '专辑A', 'picUrl': 'http://p1.music.126.net/a.jpg'},
          'dt': 1000,
        },
        '2': {'id': 2, 'name': 'B', 'ar': [], 'al': {}, 'dt': 2000},
      },
    );

    // 顺序跟随 trackIds，重复曲目保留，详情缺失的 404 被跳过。
    expect(songs.map((s) => s.name).toList(), ['A', 'B', 'A']);
    expect(songs.first.singer, '甲');
    expect(songs[1].singer, '未知歌手');
    expect(songs.first.source, 'wy');
    expect(songs.first.songmid, '1');
    expect(songs.first.duration, const Duration(milliseconds: 1000));
    expect(songs.first.artwork, 'https://p1.music.126.net/a.jpg');
    expect(songs.first.meta?['types'], ['320k', '128k']);
  });

  test('NetEase quality types derive from privilege maxbr', () {
    expect(PlaylistImportService.wyTypesFromPrivilege({'maxbr': 1999000}), [
      'flac24bit',
      'flac',
      '320k',
      '128k',
    ]);
    expect(
      PlaylistImportService.wyTypesFromPrivilege({'maxbr': 999000, 'pl': 320000}),
      ['flac', '320k', '128k'],
    );
    expect(PlaylistImportService.wyTypesFromPrivilege({'maxbr': 128000}), [
      '128k',
    ]);
    // maxbr 缺失时退回可播放码率 pl，两者都没有则给保守值。
    expect(
      PlaylistImportService.wyTypesFromPrivilege({'pl': 320000}),
      ['320k', '128k'],
    );
    expect(PlaylistImportService.wyTypesFromPrivilege(null), ['320k', '128k']);
  });
}
