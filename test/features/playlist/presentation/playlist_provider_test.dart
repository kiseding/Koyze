import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';

const playlistConsumerPaths = [
  'lib/features/playlist/presentation/playlist_provider.dart',
  'lib/features/playlist/presentation/playlist_screen.dart',
  'lib/features/playlist/presentation/playlist_detail_screen.dart',
  'lib/features/playlist/presentation/playlist_picker.dart',
  'lib/features/player/presentation/player_provider.dart',
  'lib/features/player/presentation/player_screen.dart',
  'lib/features/search/presentation/search_screen.dart',
  'lib/features/sync/presentation/sync_screen.dart',
  'lib/features/settings/presentation/settings_screen.dart',
];

void main() {
  test('playlist providers rebuild from the service revision stream', () async {
    final repository = MemoryPlaylistRepository(systemSnapshot());
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final service = container.read(playlistServiceProvider);
    await service.init();
    expect(container.read(playlistsProvider), hasLength(3));

    await service.createPlaylist(name: 'One', id: 'one');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(playlistsProvider).map((p) => p.id), contains('one'));
  });

  test(
    'production playlist consumers contain no manual version increments',
    () {
      for (final path in playlistConsumerPaths) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          isNot(contains('playlistVersionProvider')),
          reason: path,
        );
      }
    },
  );

  test('favorite playlist pages rebuild from the favorites revision stream', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_provider.dart',
    ).readAsStringSync();
    expect(source, contains("request.playlistId == 'favorites'"));
    expect(source, contains('playlistFavoritesRevisionProvider'));
  });

  test(
    'favorite provider invalidates when replaceAll removes a favorite',
    () async {
      final song = MusicItem(
        id: 'song',
        name: 'Song',
        singer: 'Singer',
        source: 'tx',
      );
      final initial = systemSnapshot();
      final favorite = initial.playlists.first.copyWith(songs: [song]);
      final repository = MemoryPlaylistRepository(
        PlaylistSnapshot(
          schemaVersion: 1,
          playlists: [favorite, initial.playlists.last],
        ),
      );
      final container = ProviderContainer(
        overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final service = container.read(playlistServiceProvider);
      await service.init();
      final subscription = container.listen(
        isSongFavoriteProvider(song.id),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await Future<void>.delayed(Duration.zero);
      expect(subscription.read().valueOrNull, isTrue);

      await service.replaceAll([
        favorite.copyWith(songs: const []),
        initial.playlists.last,
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(subscription.read().valueOrNull, isFalse);
    },
  );

  test('favoriteIdsProvider exposes the favorited id set once', () async {
    final song = MusicItem(
      id: 'song',
      name: 'Song',
      singer: 'Singer',
      source: 'tx',
    );
    final initial = systemSnapshot();
    final favorite = initial.playlists.first.copyWith(songs: [song]);
    final repository = MemoryPlaylistRepository(
      PlaylistSnapshot(
        schemaVersion: 1,
        playlists: [favorite, initial.playlists.last],
      ),
    );
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final service = container.read(playlistServiceProvider);
    await service.init();

    final ids = await container.read(favoriteIdsProvider.future);
    expect(ids, {song.identityKey, song.id});

    await service.removeSongFromPlaylist('favorites', song.identityKey);
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(favoriteIdsProvider.future), isEmpty);
  });

  test('favorite mutation only notifies favorite and sync revisions', () async {
    final repository = MemoryPlaylistRepository(systemSnapshot());
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final service = container.read(playlistServiceProvider);
    await service.init();
    var playlistRevisions = 0;
    var pageRevisions = 0;
    var recentRevisions = 0;
    var favoriteRevisions = 0;
    var syncRevisions = 0;
    final subs = [
      service.revisions.listen((_) => playlistRevisions++),
      service.pageRevisions.listen((_) => pageRevisions++),
      service.recentRevisions.listen((_) => recentRevisions++),
      service.favoritesRevisions.listen((_) => favoriteRevisions++),
      service.syncRevisions.listen((_) => syncRevisions++),
    ];
    for (final sub in subs) {
      addTearDown(sub.cancel);
    }

    await service.addSongToPlaylist(
      'favorites',
      MusicItem(id: 'song', name: 'Song', singer: 'Singer', source: 'tx'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(playlistRevisions, 1);
    expect(favoriteRevisions, 1);
    expect(syncRevisions, 0);
    expect(pageRevisions, 0);
    expect(recentRevisions, 0);
  });

  test('toggleFavoriteProvider refreshes the favorite id provider', () async {
    final repository = MemoryPlaylistRepository(systemSnapshot());
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final service = container.read(playlistServiceProvider);
    await service.init();
    final song = MusicItem(
      id: 'song',
      name: 'Song',
      singer: 'Singer',
      source: 'tx',
    );

    await container.read(toggleFavoriteProvider)(song);
    await Future<void>.delayed(Duration.zero);

    expect(
      await container.read(isSongFavoriteProvider(song.identityKey).future),
      isTrue,
    );
    expect(
      await container.read(favoriteIdsProvider.future),
      contains(song.identityKey),
    );
  });

  test('toggling a favorited song with drifted metadata unfavorites it', () async {
    final stored = MusicItem(
      id: '001',
      name: 'Song',
      singer: 'Singer',
      source: 'custom_source',
      platform: 'kw',
      songmid: '001',
    );
    final visible = MusicItem(
      id: '001',
      name: 'Song',
      singer: 'Singer',
      source: 'kw',
      platform: 'kw',
      songmid: '001',
    );
    final initial = systemSnapshot();
    final favorite = initial.playlists.first.copyWith(songs: [stored]);
    final repository = MemoryPlaylistRepository(
      PlaylistSnapshot(
        schemaVersion: 1,
        playlists: [favorite, ...initial.playlists.skip(1)],
      ),
    );
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final service = container.read(playlistServiceProvider);
    await service.init();

    expect(isFavoriteMusic(visible, await service.getAllSongs('favorites')), isTrue);

    await container.read(toggleFavoriteProvider)(visible);
    await Future<void>.delayed(Duration.zero);

    expect(await service.getAllSongs('favorites'), isEmpty);
  });

  test('optimistic favorite page removes a matching catalog track immediately', () {
    final stored = MusicItem(
      id: '001',
      name: 'Song',
      singer: 'Singer',
      source: 'custom_source',
      platform: 'kw',
      songmid: '001',
    );
    final visible = MusicItem(
      id: '001',
      name: 'Song',
      singer: 'Singer',
      source: 'kw',
      platform: 'kw',
      songmid: '001',
    );
    final page = PlaylistSongPage(total: 1, offset: 0, songs: [stored]);
    final next = applyOptimisticFavoritePage(
      page: page,
      song: visible,
      favorited: false,
    );
    expect(next.songs, isEmpty);
    expect(next.total, 0);
  });
}

PlaylistSnapshot systemSnapshot() {
  final now = DateTime.utc(2026);
  return PlaylistSnapshot(
    schemaVersion: 1,
    playlists: [
      Playlist(
        id: 'favorites',
        name: 'Favorites',
        createdAt: now,
        updatedAt: now,
      ),
      Playlist(id: 'recent', name: 'Recent', createdAt: now, updatedAt: now),
      Playlist(id: 'local', name: 'Local', createdAt: now, updatedAt: now),
    ],
  );
}

final class MemoryPlaylistRepository implements PlaylistRepository {
  MemoryPlaylistRepository(this.snapshot);

  PlaylistSnapshot snapshot;

  @override
  Future<PlaylistSnapshot> load() async => snapshot;

  @override
  Future<void> save(PlaylistSnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}
