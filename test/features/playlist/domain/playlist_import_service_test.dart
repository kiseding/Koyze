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
      'https://img1.kuwo.cn/star/albumcover/120/abc/def.jpg',
    );
    expect(
      PlaylistImportService.kwArtwork({
        'web_artistpic_short': '120/artist.jpg',
      }),
      'https://img1.kuwo.cn/star/starheads/500/artist.jpg',
    );
  });
}
