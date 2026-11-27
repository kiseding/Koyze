import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/presentation/playlist_detail_screen.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 打开歌单的第一帧就必须带着歌曲列表。
///
/// 以前歌单页用的是 `FutureProvider`：第一帧只有顶栏和一个空壳，列表要等
/// 一个 microtask 之后才补上来。那一下正好落在入场动画放到一半的位置，
/// 整页又是在实时重绘，看起来就是「打开歌单卡一下」。现在能同步切的页
/// 直接在第一帧取到，这个用例把「第一帧有歌」钉住。
void main() {
  List<MusicItem> songsOf(int count) => List.generate(
    count,
    (index) => MusicItem(
      id: 'song-$index',
      name: 'Song $index',
      singer: 'Artist $index',
      source: 'kw',
    ),
  );

  Future<ProviderContainer> pumpDetail(
    WidgetTester tester, {
    required PlaylistRepository repository,
    String playlistId = 'long',
  }) async {
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(playlistServiceProvider).init();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlaylistDetailScreen(playlistId: playlistId),
        ),
      ),
    );
    return container;
  }

  testWidgets('同步仓库：第一帧就画出歌曲，不等异步加载', (tester) async {
    final repository = _SyncPagedRepository(songsOf(120));
    await pumpDetail(tester, repository: repository);

    // 这里只 pump 过一帧，任何异步结果都还没落地。
    expect(find.text('Song 0'), findsOneWidget);
    expect(find.text('Song 1'), findsOneWidget);
    expect(repository.asyncPageRequests, isEmpty, reason: '同步能切出来的页不该再排一次异步读取');
    expect(tester.takeException(), isNull);
  });

  testWidgets('异步仓库：第一帧没有歌，落地后补上（兜底路径）', (tester) async {
    final repository = _AsyncOnlyRepository(songsOf(120));
    await pumpDetail(tester, repository: repository);

    expect(find.text('Song 0'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Song 0'), findsOneWidget);
    expect(repository.asyncPageRequests, isNotEmpty);
  });

  testWidgets('翻页仍然按页异步取，不会把整张歌单读进内存', (tester) async {
    final repository = _SyncPagedRepository(songsOf(250));
    final container = await pumpDetail(tester, repository: repository);

    final page = container
        .read(playlistServiceProvider)
        .peekSongsPage('long', offset: 100, limit: 100);
    expect(page, isNotNull);
    expect(page!.offset, 100);
    expect(page.songs.first.id, 'song-100');
    expect(page.songs.length, 100);
  });
}

Playlist _playlist(String id, int songCount) {
  final now = DateTime.utc(2026);
  return Playlist(
    id: id,
    name: 'Long',
    songs: const [],
    songCount: songCount,
    createdAt: now,
    updatedAt: now,
  );
}

final class _SyncPagedRepository
    implements
        PlaylistRepository,
        PlaylistSongPageRepository,
        SynchronousPlaylistSongPageRepository {
  _SyncPagedRepository(this.songs);

  final List<MusicItem> songs;
  final List<({int offset, int limit})> asyncPageRequests = [];

  @override
  Future<PlaylistSnapshot> load() async => PlaylistSnapshot(
    schemaVersion: 1,
    playlists: [_playlist('long', songs.length)],
  );

  @override
  Future<void> save(PlaylistSnapshot snapshot) async {}

  @override
  Future<PlaylistSongPage> loadSongsPage(
    String playlistId, {
    required int offset,
    required int limit,
  }) async {
    asyncPageRequests.add((offset: offset, limit: limit));
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
    final end = (offset + limit).clamp(0, songs.length).toInt();
    return PlaylistSongPage(
      total: songs.length,
      offset: offset,
      songs: songs.sublist(offset, end),
    );
  }
}

/// 只能异步取的仓库：详情页必须退回「先空壳、后补列表」的路径。
final class _AsyncOnlyRepository
    implements PlaylistRepository, PlaylistSongPageRepository {
  _AsyncOnlyRepository(this.songs);

  final List<MusicItem> songs;
  final List<({int offset, int limit})> asyncPageRequests = [];

  @override
  Future<PlaylistSnapshot> load() async => PlaylistSnapshot(
    schemaVersion: 1,
    playlists: [_playlist('long', songs.length)],
  );

  @override
  Future<void> save(PlaylistSnapshot snapshot) async {}

  @override
  Future<PlaylistSongPage> loadSongsPage(
    String playlistId, {
    required int offset,
    required int limit,
  }) async {
    asyncPageRequests.add((offset: offset, limit: limit));
    final end = (offset + limit).clamp(0, songs.length).toInt();
    return PlaylistSongPage(
      total: songs.length,
      offset: offset,
      songs: songs.sublist(offset, end),
    );
  }

  @override
  Future<List<MusicItem>> loadAllSongs(String playlistId) async => songs;
}
