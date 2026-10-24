import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/music_source/platform/kg_source.dart';

void main() {
  group('Kugou search parsing', () {
    test('search payload keeps fields and quality hashes', () {
      final item = KgSource.parseKugouItem({
        'SongName': '晴天',
        'FileHash': 'HASH128',
        'HQFileHash': 'HASH320',
        'SQFileHash': 'HASHFLAC',
        'AlbumName': '叶惠美',
        'AlbumID': '966846',
        'Audioid': 20505418,
        'Duration': 269,
        'Singers': [
          {'name': '周杰伦', 'id': 3520},
        ],
        'Image': 'http://imge.kugou.com/stdmusic/{size}/20230920/x.jpg',
      });

      expect(item, isNotNull);
      expect(item!.id, 'HASH128');
      expect(item.hash, 'HASH128');
      expect(item.songmid, '20505418');
      expect(item.name, '晴天');
      expect(item.singer, '周杰伦');
      expect(item.album, '叶惠美');
      expect(item.duration, const Duration(seconds: 269));
      expect(item.source, 'kg');
      expect(item.platform, 'kg');
      expect(
        item.artwork,
        'https://imge.kugou.com/stdmusic/1000/20230920/x.jpg',
      );
      expect(item.meta?['kgHash320'], 'HASH320');
      expect(item.meta?['kgHashFlac'], 'HASHFLAC');
    });

    test('rank entry falls back to filename and author_name', () {
      final item = KgSource.parseKugouItem({
        'filename': '嘉慧 - 无奈的思绪',
        'hash': 'RANK128',
        'hash_high': 'RANK320',
        'sqhash': 'RANKFLAC',
        'duration': 156,
        'authors': [
          {'author_name': '嘉慧'},
        ],
        'album_sizable_cover':
            'http://imge.kugou.com/stdmusic/{size}/cover.jpg',
      });

      expect(item, isNotNull);
      expect(item!.name, '无奈的思绪');
      expect(item.singer, '嘉慧');
      expect(item.hash, 'RANK128');
      expect(item.meta?['kgHash320'], 'RANK320');
      expect(item.meta?['kgHashFlac'], 'RANKFLAC');
      expect(
        item.artwork,
        'https://imge.kugou.com/stdmusic/1000/cover.jpg',
      );
    });

    test('entries without a hash are rejected', () {
      expect(KgSource.parseKugouItem({'SongName': '没有 hash'}), isNull);
    });
  });

  group('Kugou quality mapping', () {
    test('lossless variants share the flac attempt key', () {
      expect(KgSource.attemptKeyForQuality('flac'), 'flac');
      expect(KgSource.attemptKeyForQuality('flac24bit'), 'flac');
      expect(KgSource.attemptKeyForQuality('hires'), 'flac');
      expect(KgSource.attemptKeyForQuality('320k'), '320');
      expect(KgSource.attemptKeyForQuality('192k'), '320');
      expect(KgSource.attemptKeyForQuality('128k'), '128');
      expect(KgSource.attemptKeyForQuality('unknown'), isNull);
    });

    test('bit rate is normalised before naming the quality', () {
      expect(KgSource.qualityForBitRate(128000, 'mp3'), '128k');
      expect(KgSource.qualityForBitRate(320000, 'mp3'), '320k');
      expect(KgSource.qualityForBitRate(128, 'mp3'), '128k');
      expect(KgSource.qualityForBitRate(320, 'mp3'), '320k');
      expect(KgSource.qualityForBitRate(1029, 'flac'), 'flac');
    });

    test('artwork URL applies the requested size over https', () {
      expect(
        kugouImageUrl('http://imge.kugou.com/stdmusic/{size}/a.jpg', size: 480),
        'https://imge.kugou.com/stdmusic/480/a.jpg',
      );
      expect(kugouImageUrl('//imge.kugou.com/x/{size}/a.jpg'), isNotNull);
      expect(kugouImageUrl(''), isNull);
    });
  });
}
