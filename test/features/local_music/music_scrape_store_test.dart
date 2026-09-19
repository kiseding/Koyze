import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/local_music/domain/local_music_scraper.dart';
import 'package:koyze/features/local_music/domain/music_scrape_store.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

MusicItem _nasSong({
  String id = 'track-1',
  String source = 'emby',
  String platform = 'emby',
  String name = '稻香',
  String singer = '周杰伦',
  String album = '魔杰座',
  String? songmid,
  String? artwork,
}) {
  return MusicItem(
    id: id,
    name: name,
    singer: singer,
    album: album,
    source: source,
    platform: platform,
    songmid: songmid,
    artwork: artwork,
    duration: const Duration(seconds: 223),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MusicScrapeStore', () {
    test('overlay keeps playback identity and fills artwork/lyrics', () async {
      final storage = StorageService.forTesting(
        await SharedPreferences.getInstance(),
      );
      final store = MusicScrapeStore(storage: storage);
      await store.init();

      final song = _nasSong(songmid: 'emby-track-1');
      await store.save(song.identityKey, {
        'platform': 'tx',
        'songmid': 'tx-mid',
        'name': '稻香 (在线)',
        'singer': '周杰伦',
        'album': '魔杰座',
        'artwork': 'https://example.com/cover.jpg',
        'lyricsUrl': 'https://example.com/lyric.lrc',
        'lyrics': '[00:01.00]稻香',
      });

      final overlaid = store.overlay(song);
      expect(overlaid.source, 'emby');
      expect(overlaid.platform, 'emby');
      expect(overlaid.id, 'track-1');
      expect(overlaid.songmid, 'emby-track-1');
      expect(overlaid.identityKey, song.identityKey);
      expect(overlaid.artwork, 'https://example.com/cover.jpg');
      expect(overlaid.lyricsUrl, 'https://example.com/lyric.lrc');
      expect(overlaid.meta?['localLyrics'], '[00:01.00]稻香');
      expect(overlaid.meta?['scrapedPlatform'], 'tx');
      expect(overlaid.meta?['scrapedSongmid'], 'tx-mid');
      expect(overlaid.name, '稻香');
    });

    test('overlay fills empty title/artist from scrape identity', () async {
      final storage = StorageService.forTesting(
        await SharedPreferences.getInstance(),
      );
      final store = MusicScrapeStore(storage: storage);
      await store.init();

      final song = _nasSong(name: '  ', singer: '', album: '');
      await store.save(song.identityKey, {
        'platform': 'kw',
        'songmid': 'kw-mid',
        'name': '晴天',
        'singer': '周杰伦',
        'album': '叶惠美',
        'artwork': 'https://example.com/qingtian.jpg',
      });

      final overlaid = store.overlay(song);
      expect(overlaid.source, 'emby');
      expect(overlaid.platform, 'emby');
      expect(overlaid.name, '晴天');
      expect(overlaid.singer, '周杰伦');
      expect(overlaid.album, '叶惠美');
    });

    test('migrates legacy local and NAS scrape keys into one store', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService.forTesting(prefs);
      final song = _nasSong(songmid: 'emby-track-1');
      await storage.setJsonList('local_music_scrape_v1', [
        {
          'path': '/tmp/local.mp3',
          'platform': 'tx',
          'songmid': 'local-mid',
          'name': '本地',
          'singer': '歌手',
        },
      ]);
      await storage.setJsonList('nas_music_scrape_v1', [
        {
          'key': song.identityKey,
          'platform': 'wy',
          'songmid': 'wy-mid',
          'name': '稻香',
          'singer': '周杰伦',
          'artwork': 'https://example.com/cover.jpg',
        },
      ]);

      final store = MusicScrapeStore(storage: storage);
      await store.init();
      expect(store.identityOf('/tmp/local.mp3')?['songmid'], 'local-mid');
      expect(store.overlay(song).artwork, 'https://example.com/cover.jpg');
      expect(store.overlay(song).source, 'emby');
      expect(storage.getJsonList('music_scrape_v1'), isNotEmpty);
      expect(storage.getJsonList('local_music_scrape_v1'), isEmpty);
      expect(storage.getJsonList('nas_music_scrape_v1'), isEmpty);
    });

    test('reload from storage after a fresh store instance', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService.forTesting(prefs);
      final first = MusicScrapeStore(storage: storage);
      await first.init();
      final song = _nasSong(source: 'subsonic', platform: 'subsonic');
      await first.save(song.identityKey, {
        'platform': 'wy',
        'songmid': 'wy-mid',
        'name': '稻香',
        'singer': '周杰伦',
        'artwork': 'https://example.com/cover.jpg',
      });

      final second = MusicScrapeStore(storage: StorageService.forTesting(prefs));
      await second.init();
      final overlaid = second.overlay(song);
      expect(overlaid.artwork, 'https://example.com/cover.jpg');
      expect(overlaid.meta?['scrapedPlatform'], 'wy');
    });
  });

  group('LocalMusicScraper.trackForMusicItem', () {
    test('uses identityKey as path and NAS metadata as tags', () {
      final song = _nasSong();
      final track = LocalMusicScraper.trackForMusicItem(song);
      expect(track.path, song.identityKey);
      expect(track.title, '稻香');
      expect(track.artist, '周杰伦');
      expect(track.album, '魔杰座');
      expect(track.duration, const Duration(seconds: 223));
      expect(track.hasEmbeddedTags, isTrue);
      expect(
        LocalMusicScraper.queriesForTrack(track),
        contains(const LocalFilenameQuery(title: '稻香', artist: '周杰伦')),
      );
    });
  });
}
