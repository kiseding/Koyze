@Tags(['live'])
library;
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/music_source/platform/kw_source.dart';
import 'package:koyze/core/music_source/platform/source_utils.dart';

void main() {
  test('Kuwo request endpoints use HTTPS', () {
    expect(kuwoSearchBaseUrl, 'https://search.kuwo.cn');
    expect(kuwoArtworkEndpoint, 'https://artistpicserver.kuwo.cn/pic.web');
    expect(kuwoAntiServerEndpoint, 'https://antiserver.kuwo.cn/anti.s');
    expect(
      kuwoPlayInfoEndpoint,
      'https://www.kuwo.cn/api/v1/www/music/playInfo',
    );
    expect(kuwoLegacyPlayEndpoint, 'https://www.kuwo.cn/url');
    expect(kuwoLyricEndpoint, 'https://newlyric.kuwo.cn/newlyric.lrc');
    expect(kuwoPlaylistEndpoint, 'https://nplserver.kuwo.cn/pl.svc');
  });

  test('Kuwo search artwork resolves album and artist fields', () {
    final source = KwSource();
    addTearDown(source.dispose);

    final item = source.parseItem({
      'MUSICRID': 'MUSIC_123456',
      'SONGNAME': 'Track',
      'ARTIST': 'Artist',
      'web_albumpic_short': '120/album.jpg',
      'web_artistpic_short': '120/artist.jpg',
    }, 'kw');

    expect(
      item.artwork,
      'https://img1.kuwo.cn/star/albumcover/120/album.jpg',
    );
  });

  test('Kuwo search artwork falls back to a larger artist image', () {
    final source = KwSource();
    addTearDown(source.dispose);

    final item = source.parseItem({
      'MUSICRID': 'MUSIC_123456',
      'SONGNAME': 'Track',
      'ARTIST': 'Artist',
      'web_artistpic_short': '120/artist.jpg',
    }, 'kw');

    expect(
      item.artwork,
      'https://img1.kuwo.cn/star/starheads/500/artist.jpg',
    );
  });

  test('Kuwo direct artwork URLs are upgraded to HTTPS', () {
    expect(
      normalizeKuwoArtwork({'pic': 'http://img4.kuwo.cn/cover.jpg'}),
      'https://img4.kuwo.cn/cover.jpg',
    );
  });
}
