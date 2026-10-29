import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/local_music/domain/local_music_scanner.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('koyze_folder_art_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  String pathOf(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  /// 内容不是合法音频，扫描器会走「标签解析失败」的兜底分支——那条路径同样
  /// 应该带上文件夹封面，否则最难读标签的老格式反而最缺图。
  Future<void> writeUnparsableAudio(String name) =>
      File(pathOf(name)).writeAsBytes([0, 1, 2, 3]);

  Future<void> writeImage(String name) =>
      File(pathOf(name)).writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

  Future<LocalTrack> scanSingle() async {
    final tracks = await LocalMusicScanner().scanDirectory(tempDir.path);
    expect(tracks, hasLength(1));
    return tracks.single;
  }

  test('falls back to cover.jpg next to the track', () async {
    await writeUnparsableAudio('track.mp3');
    await writeImage('cover.jpg');

    final track = await scanSingle();

    expect(track.hasEmbeddedArtwork, isFalse);
    expect(track.folderArtworkPath, isNotNull);
    expect(track.folderArtworkPath, endsWith('cover.jpg'));
  });

  test('accepts folder.png when there is no cover', () async {
    await writeUnparsableAudio('track.flac');
    await writeImage('folder.png');

    expect((await scanSingle()).folderArtworkPath, endsWith('folder.png'));
  });

  test('prefers cover over album', () async {
    await writeUnparsableAudio('track.ogg');
    await writeImage('album.jpg');
    await writeImage('cover.jpg');

    expect((await scanSingle()).folderArtworkPath, endsWith('cover.jpg'));
  });

  test('matches an upper-case COVER.JPG', () async {
    await writeUnparsableAudio('track.m4a');
    await writeImage('COVER.JPG');

    // Windows/macOS 的文件系统不区分大小写，读回来的名字可能已被规范化为
    // 小写，所以只断言「找到了这个文件」，不比对确切文件名。
    final path = (await scanSingle()).folderArtworkPath;
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(path.toLowerCase(), endsWith('cover.jpg'));
  });

  test('ignores non-image files that share the name', () async {
    await writeUnparsableAudio('track.mp3');
    await File(pathOf('cover.txt')).writeAsString('not a picture');

    expect((await scanSingle()).folderArtworkPath, isNull);
  });

  test('returns null when the folder has no artwork', () async {
    await writeUnparsableAudio('track.mp3');

    expect((await scanSingle()).folderArtworkPath, isNull);
  });

  test('resolves one cover per directory instead of per file', () async {
    await writeUnparsableAudio('one.mp3');
    await writeUnparsableAudio('two.mp3');
    await writeImage('cover.jpg');

    final tracks = await LocalMusicScanner().scanDirectory(tempDir.path);

    expect(tracks, hasLength(2));
    for (final track in tracks) {
      expect(track.folderArtworkPath, endsWith('cover.jpg'));
    }
  });
}
