import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/network/play_url_result.dart';

void main() {
  test('QQ filename prefixes imply bitrate', () {
    expect(
      correctQualityFromUrl(
        'https://dl.stream.qqmusic.qq.com/C400xxx.m4a?vkey=1',
        'flac',
      ),
      '128k',
    );
    expect(
      correctQualityFromUrl(
        'https://dl.stream.qqmusic.qq.com/M800xxx.mp3?vkey=1',
        'flac',
      ),
      '320k',
    );
    expect(
      correctQualityFromUrl(
        'https://dl.stream.qqmusic.qq.com/F000xxx.flac?vkey=1',
        'flac',
      ),
      'flac',
    );
  });

  test('NAS native quality prefers server bitrate over requested 320k', () {
    expect(
      nasActualQuality(requested: '320k', bitRate: 128, suffix: 'mp3'),
      '128k',
    );
    expect(
      nasActualQuality(requested: '320k', bitRate: 192, suffix: 'mp3'),
      '192k',
    );
    expect(
      nasActualQuality(requested: '320k', bitRate: 320, suffix: 'mp3'),
      '320k',
    );
    expect(
      nasActualQuality(
        requested: '320k',
        bitRate: 1411,
        suffix: 'flac',
        contentType: 'audio/flac',
      ),
      'flac',
    );
    expect(
      nasActualQuality(
        requested: 'flac',
        bitRate: 1411200,
        suffix: 'flac',
      ),
      'flac',
    );
  });

  test('NAS keeps native quality even if the setting is lower', () {
    expect(
      nasActualQuality(requested: '128k', bitRate: 320, suffix: 'mp3'),
      '320k',
    );
    expect(
      nasActualQuality(requested: '192k', bitRate: 1411, container: 'flac'),
      'flac',
    );
  });

  test('NAS lossless container wins over a high mp3-like bitrate', () {
    expect(
      nasNativeQuality(bitRate: 1411, suffix: 'flac'),
      'flac',
    );
    expect(
      nasNativeQuality(bitRate: 320000, suffix: 'mp3'),
      '320k',
    );
    expect(
      nasNativeQuality(container: 'flac24bit'),
      'flac24bit',
    );
    expect(nasNativeQuality(codec: 'alac'), 'flac');
  });

  test('NAS falls back to requested when the server sent no file info', () {
    expect(nasActualQuality(requested: '320k'), '320k');
    expect(nasNativeQuality(), isNull);
  });
}
