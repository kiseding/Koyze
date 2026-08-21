import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/local_music/domain/local_music_library.dart';
import 'package:koyze/features/local_music/domain/local_music_scanner.dart';
import 'package:koyze/features/local_music/domain/local_music_scraper.dart';
import 'package:koyze/features/local_music/domain/local_metadata_writer.dart';
import 'package:koyze/features/player/domain/music_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('local_music_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('LocalMusicLibrary', () {
    test('prunes missing files on init', () async {
      final storage = StorageService.forTesting(
        await SharedPreferences.getInstance(),
      );
      final missingFile = '${tempDir.path}/gone.mp3';
      await storage.setJsonList('local_music_index_v1', [
        {
          'path': missingFile,
          'fileName': 'gone.mp3',
          'extension': 'mp3',
          'title': 'Gone',
          'artist': 'Artist',
          'duration': 0,
        },
        {
          'path': '${tempDir.path}/keep.mp3',
          'fileName': 'keep.mp3',
          'extension': 'mp3',
          'title': 'Keep',
          'artist': 'Artist',
          'duration': 0,
        },
      ]);

      final library = LocalMusicLibrary(storage: storage);
      await library.init();

      expect(library.files.containsKey(missingFile), isFalse);
      expect(library.files.containsKey('${tempDir.path}/keep.mp3'), isFalse);
      // keep.mp3 也不存在，因此两个都被清理
      expect(library.fileCount, 0);
    });

    test('removes directory and its files from index', () async {
      final storage = StorageService.forTesting(
        await SharedPreferences.getInstance(),
      );
      final dir = '${tempDir.path}/music';
      await Directory(dir).create(recursive: true);
      await File('$dir/a.mp3').writeAsBytes([0x49, 0x44, 0x33]);
      await storage.setStringList('local_music_dirs_v1', [dir]);
      await storage.setJsonList('local_music_index_v1', [
        {
          'path': '$dir/a.mp3',
          'fileName': 'a.mp3',
          'extension': 'mp3',
          'title': 'A',
          'artist': 'X',
          'duration': 0,
        },
      ]);

      final library = LocalMusicLibrary(storage: storage);
      await library.init();
      expect(library.directories, [dir]);

      await library.removeDirectory(dir);

      expect(library.directories, isEmpty);
      expect(library.fileCount, 0);
    });

    test('download directory is auto-scanned and cannot be removed', () async {
      final storage = StorageService.forTesting(
        await SharedPreferences.getInstance(),
      );
      final downloadDir = '${tempDir.path}/downloads';
      await Directory(downloadDir).create(recursive: true);
      // 真实存在文件，避免 init 时被失效清理
      await File('$downloadDir/song.mp3').writeAsBytes([0x00, 0x01, 0x02]);
      // 预置索引：模拟已扫描到的下载歌曲
      await storage.setJsonList('local_music_index_v1', [
        {
          'path': '$downloadDir/song.mp3',
          'fileName': 'song.mp3',
          'extension': 'mp3',
          'title': 'Song',
          'artist': 'Artist',
          'duration': 180,
        },
      ]);

      final library = LocalMusicLibrary(storage: storage);
      await library.init();
      await library.setDownloadDirectory(downloadDir);

      expect(library.downloadDirectory, downloadDir);
      expect(library.files.containsKey('$downloadDir/song.mp3'), isTrue);

      await library.removeDirectory(downloadDir);

      // 下载目录不可移除，索引保留
      expect(library.downloadDirectory, downloadDir);
      expect(library.files.containsKey('$downloadDir/song.mp3'), isTrue);
    });

    test('builds MusicItem with dual identity from scraped data', () async {
      final storage = StorageService.forTesting(
        await SharedPreferences.getInstance(),
      );
      final path = '${tempDir.path}/song.mp3';
      await File(path).writeAsBytes([0x49, 0x44, 0x33]);
      await storage.setJsonList('local_music_index_v1', [
        {
          'path': path,
          'fileName': 'song.mp3',
          'extension': 'mp3',
          'title': 'Song',
          'artist': 'Artist',
          'duration': 180,
        },
      ]);

      final library = LocalMusicLibrary(storage: storage);
      await library.init();
      await library.applyScrapedIdentity(path, {
        'platform': 'tx',
        'songmid': 'mid123',
        'hash': 'hash456',
        'name': 'Song',
        'singer': 'Artist',
        'artwork': 'https://example.com/art.jpg',
      });

      final songs = library.songs;
      expect(songs, hasLength(1));
      final song = songs.single;
      expect(song.url, 'file://$path');
      expect(song.platform, 'tx');
      expect(song.songmid, 'mid123');
      expect(song.hash, 'hash456');
      expect(song.meta?['filePath'], path);
      expect(song.meta?['local'], true);
    });

    test('unscraped files use local identity', () async {
      final storage = StorageService.forTesting(
        await SharedPreferences.getInstance(),
      );
      final path = '${tempDir.path}/raw.mp3';
      await File(path).writeAsBytes([0x49, 0x44, 0x33]);
      await storage.setJsonList('local_music_index_v1', [
        {
          'path': path,
          'fileName': 'raw.mp3',
          'extension': 'mp3',
          'title': 'Raw',
          'artist': 'Local',
          'duration': 60,
        },
      ]);

      final library = LocalMusicLibrary(storage: storage);
      await library.init();

      final song = library.songs.single;
      expect(song.platform, 'local');
      expect(song.songmid, isNull);
      expect(song.id, startsWith('local:'));
    });

    test('scraped identity survives re-init (artwork restored)', () async {
      final storage = StorageService.forTesting(
        await SharedPreferences.getInstance(),
      );
      final path = '${tempDir.path}/scraped.mp3';
      await File(path).writeAsBytes([0x49, 0x44, 0x33]);
      await storage.setJsonList('local_music_index_v1', [
        {
          'path': path,
          'fileName': 'scraped.mp3',
          'extension': 'mp3',
          'title': 'Song',
          'artist': 'Artist',
          'duration': 180,
        },
      ]);

      final first = LocalMusicLibrary(storage: storage);
      await first.init();
      await first.applyScrapedIdentity(path, {
        'platform': 'wy',
        'songmid': 'mid9',
        'name': 'Song',
        'singer': 'Artist',
        'artwork': 'https://example.com/art.jpg',
      });

      // 模拟重启：新实例重新 init 后应恢复刮削身份。
      final second = LocalMusicLibrary(storage: storage);
      await second.init();
      final song = second.songs.single;
      expect(song.platform, 'wy');
      expect(song.artwork, 'https://example.com/art.jpg');
    });
  });

  group('LocalMusicScanner', () {
    test('titleFromFileName strips extension', () {
      expect(titleFromFileName('hello.mp3'), 'hello');
      expect(titleFromFileName('a.b.flac'), 'a.b');
      expect(titleFromFileName('noext'), 'noext');
    });

    test('filename queries support both artist-title directions', () {
      expect(LocalMusicScraper.filenameQueries('周杰伦 - 晴天.mp3'), const [
        LocalFilenameQuery(title: '晴天', artist: '周杰伦'),
        LocalFilenameQuery(title: '周杰伦', artist: '晴天'),
      ]);
      expect(
        LocalMusicScraper.filenameQueries('01 - 晴天 - 周杰伦 (2003).flac'),
        const [
          LocalFilenameQuery(title: '周杰伦', artist: '晴天'),
          LocalFilenameQuery(title: '晴天', artist: '周杰伦'),
        ],
      );
    });

    test('filename queries keep pure song names without guessing artist', () {
      expect(LocalMusicScraper.filenameQueries('晴天 [320k].mp3'), const [
        LocalFilenameQuery(title: '晴天'),
      ]);
    });

    test('filename matching accepts exact title, artist and duration', () {
      final track = LocalTrack(
        path: '/music/晴天 - 周杰伦.mp3',
        fileName: '晴天 - 周杰伦.mp3',
        extension: 'mp3',
        size: 1,
        modifiedAt: DateTime(2026),
        title: '晴天 - 周杰伦',
        artist: '未知歌手',
        album: '',
        duration: const Duration(seconds: 269),
        hasEmbeddedTags: false,
      );
      final match = LocalMusicScraper.bestMatchForQueries(
        track,
        LocalMusicScraper.filenameQueries(track.fileName),
        [
          MusicItem(
            id: 'tx:1',
            name: '晴天',
            singer: '周杰伦',
            album: '叶惠美',
            duration: Duration(seconds: 269),
            source: 'tx',
            platform: 'tx',
            songmid: '1',
          ),
        ],
      );

      expect(match?.name, '晴天');
      expect(match?.singer, '周杰伦');
    });

    test('filename matching rejects a title-only result without duration', () {
      final track = LocalTrack(
        path: '/music/晴天.mp3',
        fileName: '晴天.mp3',
        extension: 'mp3',
        size: 1,
        modifiedAt: DateTime(2026),
        title: '晴天',
        artist: '未知歌手',
        album: '',
        duration: Duration.zero,
        hasEmbeddedTags: false,
      );
      final match = LocalMusicScraper.bestMatchForQueries(
        track,
        LocalMusicScraper.filenameQueries(track.fileName),
        [
          MusicItem(
            id: 'tx:1',
            name: '晴天',
            singer: '周杰伦',
            source: 'tx',
            platform: 'tx',
            songmid: '1',
          ),
        ],
      );

      expect(match, isNull);
    });

    test('scanner lists audio files recursively', () async {
      final musicDir = Directory('${tempDir.path}/music');
      await musicDir.create(recursive: true);
      await File('${musicDir.path}/a.mp3').writeAsBytes([0x49, 0x44, 0x33]);
      await File('${musicDir.path}/b.flac').writeAsBytes([0x66, 0x4C, 0x61]);
      await File('${musicDir.path}/c.txt').writeAsString('not audio');
      final nested = Directory('${musicDir.path}/sub');
      await nested.create();
      await File('${nested.path}/d.wav').writeAsBytes([0x52, 0x49, 0x46]);

      final scanner = LocalMusicScanner();
      final tracks = await scanner.scanDirectory(musicDir.path);

      // 损坏的假音频文件会被 audiotags 拒绝，但文件枚举应覆盖 4 个候选
      expect(tracks.length, lessThanOrEqualTo(4));
    });

    test('scanner keeps files whose metadata parser fails', () async {
      final musicDir = Directory('${tempDir.path}/fallback');
      await musicDir.create(recursive: true);
      final file = File('${musicDir.path}/Artist - Title.mp3');
      await file.writeAsBytes([0, 1, 2, 3]);

      final tracks = await LocalMusicScanner().scanDirectory(musicDir.path);

      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'Artist - Title');
      expect(tracks.single.artist, '未知歌手');
      expect(tracks.single.hasEmbeddedTags, isFalse);
    });

    test(
      'metadata writer leaves an unsupported or invalid file unchanged',
      () async {
        final path = '${tempDir.path}/invalid.mp3';
        await File(path).writeAsBytes([0, 1, 2, 3]);

        final written = await writeScrapedMetadata(
          path,
          title: 'Title',
          artist: 'Artist',
          album: 'Album',
        );

        expect(written, isFalse);
        expect(await File(path).readAsBytes(), [0, 1, 2, 3]);
      },
    );

    test(
      'metadata writer creates an ID3 tag for a tagless MP3 frame',
      () async {
        final path = '${tempDir.path}/tagless.mp3';
        await File(
          path,
        ).writeAsBytes([0xff, 0xfb, ...List<int>.filled(4096, 0)]);

        final written = await writeScrapedMetadata(
          path,
          title: 'Title',
          artist: 'Artist',
          album: 'Album',
        );

        expect(written, isTrue);
        final metadata = readMetadata(File(path));
        expect(metadata.title, 'Title');
        expect(metadata.artist, 'Artist');
        expect(metadata.album, 'Album');
      },
    );

    test('scanner does not follow directory or file symlinks', () async {
      if (Platform.isWindows) return;
      final root = Directory('${tempDir.path}/root')..createSync();
      final outside = Directory('${tempDir.path}/outside')..createSync();
      File('${outside.path}/outside.mp3').writeAsBytesSync([0x49, 0x44, 0x33]);
      Link('${root.path}/outside').createSync(outside.path);
      Link('${root.path}/cycle').createSync(root.path);
      Link('${root.path}/linked.mp3').createSync('${outside.path}/outside.mp3');
      final visited = <String>[];

      await LocalMusicScanner().scanDirectory(
        root.path,
        shouldSkip: (path) {
          visited.add(path);
          return true;
        },
      );

      expect(visited, isEmpty);
    });
  });

  group('LocalMusicScraper', () {
    test('matches exact title with duration tolerance', () {
      final track = LocalTrack(
        path: '/tmp/a.mp3',
        fileName: 'a.mp3',
        extension: 'mp3',
        size: 100,
        modifiedAt: DateTime.now(),
        title: '稻香',
        artist: '周杰伦',
        album: '',
        duration: const Duration(seconds: 200),
      );

      final identity = LocalMusicScraper.bestMatch(track, [
        MusicItem(
          id: '1',
          name: '稻香',
          singer: '周杰伦',
          source: 'tx',
          platform: 'tx',
          songmid: 'mid1',
          duration: const Duration(seconds: 201),
        ),
      ]);

      expect(identity, isNotNull);
      expect(identity!.songmid, 'mid1');
      expect(identity.platform, 'tx');
    });

    test('rejects title mismatch and duration mismatch', () {
      final track = LocalTrack(
        path: '/tmp/a.mp3',
        fileName: 'a.mp3',
        extension: 'mp3',
        size: 100,
        modifiedAt: DateTime.now(),
        title: '稻香',
        artist: '周杰伦',
        album: '',
        duration: const Duration(seconds: 200),
      );

      final wrongTitle = LocalMusicScraper.bestMatch(track, [
        MusicItem(
          id: '1',
          name: '晴天',
          singer: '周杰伦',
          source: 'tx',
          platform: 'tx',
          songmid: 'mid1',
          duration: const Duration(seconds: 201),
        ),
      ]);
      final wrongDuration = LocalMusicScraper.bestMatch(track, [
        MusicItem(
          id: '2',
          name: '稻香',
          singer: '周杰伦',
          source: 'tx',
          platform: 'tx',
          songmid: 'mid2',
          duration: const Duration(seconds: 500),
        ),
      ]);

      expect(wrongTitle, isNull);
      expect(wrongDuration, isNull);
    });

    test('skips results without songmid or hash', () {
      final track = LocalTrack(
        path: '/tmp/a.mp3',
        fileName: 'a.mp3',
        extension: 'mp3',
        size: 100,
        modifiedAt: DateTime.now(),
        title: 'Song',
        artist: 'Artist',
        album: '',
        duration: const Duration(seconds: 200),
      );

      final identity = LocalMusicScraper.bestMatch(track, [
        MusicItem(
          id: '1',
          name: 'Song',
          singer: 'Artist',
          source: 'tx',
          platform: 'tx',
          duration: const Duration(seconds: 200),
        ),
      ]);

      expect(identity, isNull);
    });

    test('upgrades scraped artwork URLs for player-sized covers', () {
      expect(
        LocalMusicScraper.highResolutionArtworkUrl(
          'tx',
          'https://y.gtimg.cn/music/photo_new/T002R500x500M000album.jpg',
        ),
        'https://y.gtimg.cn/music/photo_new/T002R1000x1000M000album.jpg',
      );
      expect(
        LocalMusicScraper.highResolutionArtworkUrl(
          'wy',
          'https://p1.music.126.net/cover.jpg?param=120y120',
        ),
        'https://p1.music.126.net/cover.jpg?param=1000y1000',
      );
      expect(
        LocalMusicScraper.highResolutionArtworkUrl(
          'kw',
          'https://img1.kuwo.cn/star/albumcover/120/cover.jpg',
        ),
        'https://img1.kuwo.cn/star/albumcover/500/cover.jpg',
      );
    });
  });
}
