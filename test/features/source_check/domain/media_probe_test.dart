import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/source_check/domain/media_probe.dart';

void main() {
  group('content-range', () {
    test('takes the total after the slash, not the segment length', () {
      // 片段是 64 KiB，总长 8.1 MB：拿 65536 去比时长会误判成试听片段。
      expect(
        HttpMediaProbe.totalBytesOf('bytes 0-65535/8123456'),
        equals(8123456),
      );
      expect(
        HttpMediaProbe.totalBytesOf('bytes 0-65535/8123456 '),
        equals(8123456),
      );
    });

    test('returns null when the total is unknown or unusable', () {
      expect(HttpMediaProbe.totalBytesOf(null), isNull);
      expect(HttpMediaProbe.totalBytesOf(''), isNull);
      expect(HttpMediaProbe.totalBytesOf('bytes 0-0/*'), isNull);
      expect(HttpMediaProbe.totalBytesOf('bytes 0-0/0'), isNull);
      expect(HttpMediaProbe.totalBytesOf('bytes 0-1023'), isNull);
    });
  });

  group('classify', () {
    test('trusts the magic bytes over content-type', () {
      final result = HttpMediaProbe.classify(
        url: 'https://cdn.example.com/stream?id=1',
        bytes: [0x66, 0x4c, 0x61, 0x43, 0, 0, 0, 0],
        // 国内 CDN 经常这么标音频。
        responseHeaders: {
          'content-type': 'application/octet-stream',
          'content-range': 'bytes 0-7/5300000',
        },
      );

      expect(result.ok, isTrue);
      expect(result.extension, equals('.flac'));
      expect(result.sizeBytes, equals(5300000));
    });

    test('falls back to the URL extension when the magic is unknown', () {
      final result = HttpMediaProbe.classify(
        url: 'https://cdn.example.com/a/b.mp3?token=abc',
        bytes: [0x00, 0x01, 0x02, 0x03],
        responseHeaders: const {},
      );

      expect(result.ok, isTrue);
      expect(result.extension, equals('.mp3'));
      expect(result.sizeBytes, isNull);
    });

    test('rejects a payload that is neither audio nor audio-named', () {
      // 防盗链常见做法：返回一段 HTML 或 JS 提示页。
      final result = HttpMediaProbe.classify(
        url: 'https://cdn.example.com/play/123',
        bytes: '<html><body>forbidden</body></html>'.codeUnits,
        responseHeaders: const {'content-type': 'audio/mpeg'},
      );

      expect(result.ok, isFalse);
      expect(result.extension, isNull);
      expect(result.message, contains('不是音频'));
    });
  });

  test('audioExtensionOf ignores the query string', () {
    expect(
      HttpMediaProbe.audioExtensionOf('https://a.com/x.flac?sign=1.mp3'),
      equals('.flac'),
    );
    expect(HttpMediaProbe.audioExtensionOf('https://a.com/x'), isNull);
  });
}
