import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/domain/m3u_import.dart';
import 'package:koyze/features/playlist/domain/m3u_playlist.dart';
import 'package:koyze/features/player/domain/music_item.dart';

MusicItem local(String path, String title, String artist) => MusicItem(
  id: 'local:$path',
  name: title,
  singer: artist,
  source: 'local',
  platform: 'local',
  url: Uri.file(path).toString(),
  meta: {'filePath': path, 'local': true},
);

void main() {
  final library = [
    local(r'C:\Music\Jay\qingtian.flac', '晴天', '周杰伦'),
    local(r'C:\Music\Jay\daoxiang.flac', '稻香', '周杰伦'),
    local('/music/adele/hello.mp3', 'Hello', 'Adele'),
  ];

  test('matches by exact path regardless of separators and case', () {
    // 别的播放器写的是正斜杠 + 小写盘符，仍然要认得。
    final doc = parseM3u('#EXTINF:1,x\nc:/music/jay/qingtian.flac');

    final result = matchM3uToLibrary(doc, library);

    expect(result.songs, hasLength(1));
    expect(result.songs.single.name, '晴天');
    expect(result.skipped, 0);
  });

  test('matches a file:// uri location', () {
    final doc = parseM3u('#EXTINF:1,x\n${Uri.file('/music/adele/hello.mp3')}');

    final result = matchM3uToLibrary(doc, library);

    expect(result.songs.single.name, 'Hello');
  });

  test('falls back to title and artist when the path is foreign', () {
    final doc = parseM3u('#EXTINF:200,周杰伦 - 稻香\n/mnt/other/daoxiang.flac');

    final result = matchM3uToLibrary(doc, library);

    expect(result.songs.single.name, '稻香');
    expect(result.skipped, 0);
  });

  test('title-only entries match when the title is unique', () {
    final doc = parseM3u('#EXTINF:1,Hello\n/somewhere/hello.mp3');

    final result = matchM3uToLibrary(doc, library);

    expect(result.songs.single.name, 'Hello');
  });

  test('title-only entries are skipped when the title is ambiguous', () {
    final doc = parseM3u('#EXTINF:1,晴天\n/a.mp3');
    final duplicates = [
      ...library,
      local('/other/qingtian2.flac', '晴天', '翻唱'),
    ];

    final result = matchM3uToLibrary(doc, duplicates);

    expect(result.songs, isEmpty);
    expect(result.skipped, 1);
  });

  test('counts unmatched entries as skipped', () {
    final doc = parseM3u(
      '#EXTINF:1,不存在的歌 - 没这个人\n/a.mp3\n'
      '#EXTINF:1,周杰伦 - 晴天\n/b.mp3',
    );

    final result = matchM3uToLibrary(doc, library);

    expect(result.songs, hasLength(1));
    expect(result.skipped, 1);
  });

  test('does not add the same song twice', () {
    final doc = parseM3u(
      '#EXTINF:1,周杰伦 - 晴天\n/a.mp3\n'
      '#EXTINF:1,周杰伦 - 晴天\n/b.mp3',
    );

    final result = matchM3uToLibrary(doc, library);

    expect(result.songs, hasLength(1));
  });

  test('adds malformed records to the skipped count', () {
    final doc = parseM3u('#EXTINF:1,orphan\n#EXTINF:1,周杰伦 - 晴天\n/a.mp3');

    final result = matchM3uToLibrary(doc, library);

    expect(result.songs, hasLength(1));
    expect(result.skipped, 1);
  });

  test('is case-insensitive on names', () {
    final doc = parseM3u('#EXTINF:1,ADELE - hello\n/a.mp3');

    final result = matchM3uToLibrary(doc, library);

    expect(result.songs.single.name, 'Hello');
  });

  test('an empty document imports nothing', () {
    final result = matchM3uToLibrary(parseM3u('#EXTM3U\n'), library);

    expect(result.isEmpty, isTrue);
    expect(result.skipped, 0);
  });
}
