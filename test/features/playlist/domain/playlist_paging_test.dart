import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/domain/playlist_service.dart';

void main() {
  test(
    'loads only the requested playlist page from a paged repository',
    () async {
      final songs = List.generate(250, _song);
      final repository = _PagedRepository(songs);
      final service = PlaylistService(repository: repository);
      await service.init();

      final page = await service.getSongsPage('long', offset: 100, limit: 100);

      expect(page.total, 250);
      expect(page.offset, 100);
      expect(
        page.songs.map((song) => song.id),
        List.generate(100, (index) => '${index + 100}'),
      );
      expect(repository.pageRequests, [(offset: 100, limit: 100)]);
      await service.dispose();
    },
  );

  test('同步仓库能直接切出一页，命中缓存后不再重复解码', () async {
    final songs = List.generate(250, _song);
    final repository = _SyncPagedRepository(songs);
    final service = PlaylistService(repository: repository);
    await service.init();

    final page = service.peekSongsPage('long', offset: 100, limit: 100);

    expect(page, isNotNull);
    expect(page!.total, 250);
    expect(page.offset, 100);
    expect(
      page.songs.map((song) => song.id),
      List.generate(100, (index) => '${index + 100}'),
    );
    expect(repository.peekCount, 1);
    expect(repository.pageRequests, isEmpty, reason: '能同步切页就不该再走异步');

    final again = service.peekSongsPage('long', offset: 100, limit: 100);
    expect(identical(again, page), isTrue);
    expect(repository.peekCount, 1, reason: '同一页第二次应直接命中缓存');
    await service.dispose();
  });

  test('歌单被改动后同步缓存立刻作废', () async {
    final songs = List.generate(250, _song);
    final repository = _SyncPagedRepository(songs);
    final service = PlaylistService(repository: repository);
    await service.init();

    expect(service.peekSongsPage('long', offset: 0, limit: 100), isNotNull);
    expect(repository.peekCount, 1);

    await service.updatePlaylist(id: 'long', name: 'Renamed');

    expect(service.peekSongsPage('long', offset: 0, limit: 100), isNotNull);
    expect(repository.peekCount, 2, reason: '改动之后必须重新解码，不能把旧列表当新数据画出来');
    await service.dispose();
  });

  test('只能异步取的仓库，同步入口返回 null', () async {
    final service = PlaylistService(
      repository: _PagedRepository(List.generate(10, _song)),
    );
    await service.init();

    expect(service.peekSongsPage('long', offset: 0, limit: 100), isNull);
    await service.dispose();
  });
}

MusicItem _song(int index) => MusicItem(
  id: '$index',
  name: 'Song $index',
  singer: 'Singer',
  source: 'test',
);

final class _PagedRepository
    implements PlaylistRepository, PlaylistSongPageRepository {
  _PagedRepository(this.songs);

  final List<MusicItem> songs;
  final List<({int offset, int limit})> pageRequests = [];

  @override
  Future<PlaylistSnapshot> load() async {
    final now = DateTime.utc(2026);
    return PlaylistSnapshot(
      schemaVersion: 1,
      playlists: [
        Playlist(
          id: 'long',
          name: 'Long',
          songs: const [],
          songCount: songs.length,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }

  @override
  Future<PlaylistSongPage> loadSongsPage(
    String playlistId, {
    required int offset,
    required int limit,
  }) async {
    pageRequests.add((offset: offset, limit: limit));
    return PlaylistSongPage(
      total: songs.length,
      offset: offset,
      songs: songs.sublist(
        offset,
        (offset + limit).clamp(0, songs.length).toInt(),
      ),
    );
  }

  @override
  Future<List<MusicItem>> loadAllSongs(String playlistId) async => songs;

  @override
  Future<void> save(PlaylistSnapshot snapshot) async {}
}

/// 已经把整份歌单读进内存、能同步切页的仓库（生产环境是
/// `FilePlaylistRepository`：启动时整份 JSON 就在内存里）。
final class _SyncPagedRepository
    implements
        PlaylistRepository,
        PlaylistSongPageRepository,
        SynchronousPlaylistSongPageRepository {
  _SyncPagedRepository(this.songs);

  final List<MusicItem> songs;
  final List<({int offset, int limit})> pageRequests = [];
  int peekCount = 0;

  @override
  Future<PlaylistSnapshot> load() async {
    final now = DateTime.utc(2026);
    return PlaylistSnapshot(
      schemaVersion: 1,
      playlists: [
        Playlist(
          id: 'long',
          name: 'Long',
          songs: const [],
          songCount: songs.length,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }

  @override
  Future<PlaylistSongPage> loadSongsPage(
    String playlistId, {
    required int offset,
    required int limit,
  }) async {
    pageRequests.add((offset: offset, limit: limit));
    return peekSongsPage(playlistId, offset: offset, limit: limit)!;
  }

  @override
  Future<List<MusicItem>> loadAllSongs(String playlistId) async => songs;

  @override
  PlaylistSongPage? peekSongsPage(
    String playlistId, {
    required int offset,
    required int limit,
  }) {
    peekCount += 1;
    final end = (offset + limit).clamp(0, songs.length).toInt();
    return PlaylistSongPage(
      total: songs.length,
      offset: offset,
      songs: songs.sublist(offset, end),
    );
  }

  @override
  Future<void> save(PlaylistSnapshot snapshot) async {}
}
