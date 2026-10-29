import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/domain/m3u_playlist.dart';

void main() {
  group('parseM3u', () {
    test('reads extensions and paths', () {
      const content = '''
#EXTM3U
#EXTINF:245,周杰伦 - 晴天
/music/jay/qingtian.flac
#EXTINF:198,稻香
/music/jay/daoxiang.flac
''';

      final doc = parseM3u(content);

      expect(doc.entries, hasLength(2));
      expect(doc.droppedLines, 0);
      final first = doc.entries.first;
      expect(first.location, '/music/jay/qingtian.flac');
      expect(first.artist, '周杰伦');
      expect(first.title, '晴天');
      expect(first.duration, const Duration(seconds: 245));

      // 只有标题没有歌手时，整段当标题，不要把歌名当成歌手。
      expect(doc.entries.last.artist, isNull);
      expect(doc.entries.last.title, '稻香');
    });

    test('accepts entries without any #EXTINF', () {
      const content = '/music/a.mp3\n/music/b.mp3\n';

      final doc = parseM3u(content);

      expect(doc.entries, hasLength(2));
      expect(doc.entries.first.title, isNull);
      expect(doc.entries.first.duration, isNull);
    });

    test('treats -1 as a stream with no duration', () {
      const content = '#EXTINF:-1,Live Radio\nhttps://example.com/live.mp3';

      final doc = parseM3u(content);

      expect(doc.entries.single.duration, isNull);
      expect(doc.entries.single.title, 'Live Radio');
      expect(doc.entries.single.location, 'https://example.com/live.mp3');
    });

    test('keeps fractional seconds', () {
      final doc = parseM3u('#EXTINF:245.6,x\n/a.mp3');

      expect(doc.entries.single.duration, const Duration(seconds: 246));
    });

    test('expands relative paths against the playlist directory', () {
      final doc = parseM3u(
        'song.flac\nsub/other.flac',
        baseDirectory: r'C:\Music',
      );

      expect(doc.entries.first.location, r'C:\Music/song.flac');
      expect(doc.entries.last.location, r'C:\Music/sub/other.flac');
    });

    test('leaves absolute paths and urls alone', () {
      final doc = parseM3u(
        'https://example.com/a.mp3\n'
        r'D:\Music\b.flac'
        '\n/mnt/c.mp3',
        baseDirectory: '/base',
      );

      expect(doc.entries[0].location, 'https://example.com/a.mp3');
      expect(doc.entries[1].location, r'D:\Music\b.flac');
      expect(doc.entries[2].location, '/mnt/c.mp3');
    });

    test('counts a dangling #EXTINF as a dropped record', () {
      const content = '#EXTINF:100,orphan\n#EXTINF:200,kept\n/a.mp3';

      final doc = parseM3u(content);

      expect(doc.entries, hasLength(1));
      expect(doc.entries.single.title, 'kept');
      expect(doc.droppedLines, 1);
    });

    test('ignores other directives without counting them as broken', () {
      const content = '''
#EXTM3U
#PLAYLIST:My List
#EXTINF:10,A
#EXTVLCOPT:start-time=3
/a.mp3
''';

      final doc = parseM3u(content);

      expect(doc.entries, hasLength(1));
      expect(doc.droppedLines, 0);
    });

    test('only splits on " - " with spaces', () {
      final doc = parseM3u('#EXTINF:1,AC/DC\n/a.mp3\n#EXTINF:1,A - B\n/b.mp3');

      // 没有「 - 」时不猜歌手，避免把连字符歌名拆坏。
      expect(doc.entries.first.artist, isNull);
      expect(doc.entries.first.title, 'AC/DC');
      expect(doc.entries.last.artist, 'A');
      expect(doc.entries.last.title, 'B');
    });

    test('handles CRLF and blank lines', () {
      final doc = parseM3u('#EXTM3U\r\n\r\n#EXTINF:5,x\r\n/a.mp3\r\n');

      expect(doc.entries, hasLength(1));
      expect(doc.entries.single.location, '/a.mp3');
    });
  });

  group('buildM3u', () {
    test('writes a header and one EXTINF per entry', () {
      final text = buildM3u([
        const M3uEntry(
          location: '/music/a.flac',
          title: '晴天',
          artist: '周杰伦',
          duration: Duration(seconds: 245),
        ),
        const M3uEntry(location: 'https://example.com/b.mp3'),
      ]);

      final lines = text.trim().split('\n');
      expect(lines.first, '#EXTM3U');
      expect(lines[1], '#EXTINF:245,周杰伦 - 晴天');
      expect(lines[2], '/music/a.flac');
      expect(lines[3], '#EXTINF:-1,https://example.com/b.mp3');
      expect(lines[4], 'https://example.com/b.mp3');
    });

    test('round-trips through the parser', () {
      final original = [
        const M3uEntry(
          location: '/a.mp3',
          title: 'One',
          artist: 'Artist',
          duration: Duration(seconds: 30),
        ),
        const M3uEntry(location: '/b.mp3', title: 'Two'),
      ];

      final parsed = parseM3u(buildM3u(original));

      expect(parsed.entries, hasLength(2));
      expect(parsed.entries.first.location, '/a.mp3');
      expect(parsed.entries.first.artist, 'Artist');
      expect(parsed.entries.first.title, 'One');
      expect(parsed.entries.first.duration, const Duration(seconds: 30));
      expect(parsed.entries.last.title, 'Two');
      expect(parsed.droppedLines, 0);
    });
  });

  group('decodeM3uBytes', () {
    test('reads plain UTF-8', () {
      final bytes = Uint8List.fromList(
        utf8.encode('#EXTM3U\n/a.mp3'),
      );

      expect(decodeM3uBytes(bytes), contains('/a.mp3'));
    });

    test('strips the UTF-8 BOM', () {
      final bytes = Uint8List.fromList([
        0xEF, 0xBB, 0xBF,
        ...utf8.encode('#EXTM3U'),
      ]);

      expect(decodeM3uBytes(bytes), startsWith('#EXTM3U'));
    });

    test('decodes UTF-16LE with a BOM', () {
      const text = '#EXTINF:1,晴天';
      final body = <int>[];
      for (final unit in text.codeUnits) {
        body
          ..add(unit & 0xFF)
          ..add((unit >> 8) & 0xFF);
      }

      expect(decodeM3uBytes(Uint8List.fromList([0xFF, 0xFE, ...body])), text);
    });

    test('falls back to latin1 instead of throwing', () {
      final bytes = Uint8List.fromList([0xC4, 0xE3, 0x0A]);

      expect(() => decodeM3uBytes(bytes), returnsNormally);
    });
  });
}
