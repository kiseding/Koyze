import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/domain/text_playlist.dart';

void main() {
  group('detectPlaylistFormat', () {
    test('reads the extension first', () {
      expect(
        detectPlaylistFormat('roadtrip.m3u8', ''),
        PlaylistTextFormat.m3u8,
      );
      expect(detectPlaylistFormat('roadtrip.pls', ''), PlaylistTextFormat.pls);
      expect(detectPlaylistFormat('a.wpl', ''), PlaylistTextFormat.wpl);
      expect(detectPlaylistFormat('a.wax', ''), PlaylistTextFormat.asx);
    });

    test('sniffs the content when the extension is missing or generic', () {
      expect(
        detectPlaylistFormat('playlist', '#EXTM3U\n#EXTINF:1,A\n/a.mp3'),
        PlaylistTextFormat.m3u,
      );
      expect(
        detectPlaylistFormat('playlist.txt', '[playlist]\nFile1=/a.mp3'),
        PlaylistTextFormat.pls,
      );
      expect(
        detectPlaylistFormat(
          'playlist.txt',
          '<?xml version="1.0"?><playlist version="1" '
              'xmlns="http://xspf.org/ns/0/"><trackList/></playlist>',
        ),
        PlaylistTextFormat.xspf,
      );
    });
  });

  group('parseTextPlaylist', () {
    test('rejects audio files by extension', () {
      expect(
        () => parseTextPlaylist(fileName: '晴天.flac', content: 'fLaC....'),
        throwsA(
          isA<PlaylistFileException>().having(
            (error) => error.failure,
            'failure',
            PlaylistReadFailure.audioFile,
          ),
        ),
      );
    });

    test('rejects binary content with a text extension', () {
      final content = String.fromCharCodes([0x00, 0x01, 0x02, 0x03]);
      expect(
        () => parseTextPlaylist(fileName: 'list.txt', content: content),
        throwsA(
          isA<PlaylistFileException>().having(
            (error) => error.failure,
            'failure',
            PlaylistReadFailure.binaryFile,
          ),
        ),
      );
    });

    test('reports an empty playlist instead of a generic failure', () {
      expect(
        () => parseTextPlaylist(fileName: 'empty.m3u', content: '#EXTM3U\n'),
        throwsA(
          isA<PlaylistFileException>().having(
            (error) => error.failure,
            'failure',
            PlaylistReadFailure.empty,
          ),
        ),
      );
    });

    test('reports malformed XML', () {
      expect(
        () => parseTextPlaylist(
          fileName: 'broken.xspf',
          content: '<playlist><trackList>',
        ),
        throwsA(
          isA<PlaylistFileException>().having(
            (error) => error.failure,
            'failure',
            PlaylistReadFailure.malformed,
          ),
        ),
      );
    });

    test('parses PLS with titles, lengths and sparse indexes', () {
      const content = '''
[playlist]
NumberOfEntries=2
File1=C:\\Music\\qingtian.flac
Title1=周杰伦 - 晴天
Length1=245
File3=/music/daoxiang.flac
Title3=稻香
''';
      final parsed = parseTextPlaylist(fileName: 'list.pls', content: content);

      expect(parsed.format, PlaylistTextFormat.pls);
      expect(parsed.document.entries, hasLength(2));
      final first = parsed.document.entries.first;
      expect(first.location, r'C:\Music\qingtian.flac');
      expect(first.artist, '周杰伦');
      expect(first.title, '晴天');
      expect(first.duration, const Duration(seconds: 245));
      // 序号不连续时按序号排序，而不是按文件里的出现顺序。
      expect(parsed.document.entries.last.title, '稻香');
    });

    test('parses XSPF locations and millisecond durations', () {
      const content = '''
<?xml version="1.0" encoding="UTF-8"?>
<playlist version="1" xmlns="http://xspf.org/ns/0/">
  <trackList>
    <track>
      <location>file:///C:/Music/qingtian.flac</location>
      <title>晴天</title>
      <creator>周杰伦</creator>
      <duration>245000</duration>
    </track>
    <track>
      <title>没有路径</title>
    </track>
  </trackList>
</playlist>
''';
      final parsed = parseTextPlaylist(fileName: 'list.xspf', content: content);

      expect(parsed.document.entries, hasLength(1));
      final entry = parsed.document.entries.single;
      expect(entry.title, '晴天');
      expect(entry.artist, '周杰伦');
      expect(entry.duration, const Duration(seconds: 245));
      expect(entry.location, contains('qingtian.flac'));
      expect(parsed.document.droppedLines, 1);
    });

    test('parses WPL media entries and guesses titles from paths', () {
      const content = '''
<?xml version="1.0" encoding="UTF-8"?>
<wpl version="1.0">
  <title>My List</title>
  <media src="C:\\Music\\01 - 周杰伦 - 晴天.flac" tid="{x}"/>
  <media src="C:\\Music\\daoxiang.mp3"/>
</wpl>
''';
      final parsed = parseTextPlaylist(fileName: 'list.wpl', content: content);

      expect(parsed.format, PlaylistTextFormat.wpl);
      expect(parsed.document.entries, hasLength(2));
      expect(parsed.document.entries.first.artist, '周杰伦');
      expect(parsed.document.entries.first.title, '晴天');
      // 文件名里没有「歌手 - 歌名」时整段当标题。
      expect(parsed.document.entries.last.title, 'daoxiang');
    });

    test('parses ASX entries with href and duration', () {
      const content = '''
<ASX version="3.0">
  <ENTRY>
    <TITLE>晴天</TITLE>
    <AUTHOR>周杰伦</AUTHOR>
    <REF HREF="file:///C:/Music/qingtian.flac"/>
    <DURATION value="0:04:05"/>
  </ENTRY>
</ASX>
''';
      final parsed = parseTextPlaylist(fileName: 'list.asx', content: content);

      expect(parsed.format, PlaylistTextFormat.asx);
      final entry = parsed.document.entries.single;
      expect(entry.title, '晴天');
      expect(entry.artist, '周杰伦');
      expect(entry.duration, const Duration(minutes: 4, seconds: 5));
      expect(entry.location, contains('qingtian.flac'));
    });

    test('parses a plain TXT list of names and paths', () {
      const content = '''
1. 周杰伦 - 晴天
02、稻香
/music/jay/daoxiang.flac
''';
      final parsed = parseTextPlaylist(
        fileName: 'backup.txt',
        content: content,
        baseDirectory: '/music',
      );

      expect(parsed.format, PlaylistTextFormat.txt);
      expect(parsed.document.entries, hasLength(3));
      expect(parsed.document.entries[0].artist, '周杰伦');
      expect(parsed.document.entries[0].title, '晴天');
      // 不带「歌名 - 歌手」的文字行整段当标题。
      expect(parsed.document.entries[1].artist, isNull);
      expect(parsed.document.entries[1].title, '稻香');
      expect(parsed.document.entries[2].location, '/music/jay/daoxiang.flac');
      expect(parsed.document.entries[2].title, 'daoxiang');
    });

    test('still parses M3U through the dispatcher', () {
      const content = '#EXTM3U\n#EXTINF:245,周杰伦 - 晴天\n/a.flac';
      final parsed = parseTextPlaylist(fileName: 'a.m3u', content: content);

      expect(parsed.format, PlaylistTextFormat.m3u);
      expect(parsed.document.entries.single.title, '晴天');
    });
  });
}
