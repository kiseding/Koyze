import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/presentation/playlist_detail_screen.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/player/domain/player_service.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const promptDismissedKey = 'local_music_artwork_prompt_dismissed';

  Playlist localPlaylist(List<MusicItem> songs) {
    final now = DateTime.utc(2026);
    return Playlist(
      id: 'local',
      name: 'Local music',
      createdAt: now,
      updatedAt: now,
      songs: songs,
    );
  }

  List<MusicItem> songsWithMissingArtwork(int total, int missing) =>
      List.generate(
        total,
        (index) => MusicItem(
          id: 'song-$index',
          name: 'Song $index',
          singer: 'Artist $index',
          source: 'local',
          artwork: index < missing ? null : 'file:///cover-$index.jpg',
        ),
      );

  Future<StorageService> pumpLocalPlaylist(
    WidgetTester tester,
    List<MusicItem> songs, {
    bool dismissed = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (dismissed) promptDismissedKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    final storage = StorageService.forTesting(preferences);
    final repository = _MemoryRepository(
      PlaylistSnapshot(schemaVersion: 1, playlists: [localPlaylist(songs)]),
    );
    final container = ProviderContainer(
      overrides: [
        playlistRepositoryProvider.overrideWithValue(repository),
        playerServiceProvider.overrideWithValue(PlayerService()),
        localArtworkPromptStorageProvider.overrideWith((ref) async => storage),
      ],
    );
    addTearDown(container.dispose);
    await container.read(playlistServiceProvider).init();

    final router = GoRouter(
      initialLocation: '/playlist/detail/local',
      routes: [
        GoRoute(
          path: '/playlist/detail/:playlistId',
          builder: (_, state) => PlaylistDetailScreen(
            playlistId: state.pathParameters['playlistId']!,
          ),
        ),
        GoRoute(
          path: '/local-music',
          builder: (_, _) => const Scaffold(body: Text('Local music settings')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return storage;
  }

  testWidgets(
    'empty local playlist shows centered add-folder action and opens settings',
    (tester) async {
      await pumpLocalPlaylist(tester, const []);

      final button = find.widgetWithText(FilledButton, 'Add folder');
      expect(button, findsOneWidget);
      expect(find.text('No songs'), findsNothing);

      final center = tester.getCenter(button);
      final size = tester.getSize(button);
      expect(center.dx, closeTo(400, 1));
      expect(center.dy, greaterThan(100));
      expect(size.width, greaterThan(100));

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Local music settings'), findsOneWidget);
    },
  );

  testWidgets(
    'prompts when exactly 30 percent of all local songs lack artwork',
    (tester) async {
      await pumpLocalPlaylist(tester, songsWithMissingArtwork(10, 3));

      expect(find.text('Add artwork to local music'), findsOneWidget);
      expect(find.text("Don't remind me again"), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    },
  );

  testWidgets('does not prompt below 30 percent', (tester) async {
    await pumpLocalPlaylist(tester, songsWithMissingArtwork(10, 2));

    expect(find.text('Add artwork to local music'), findsNothing);
  });

  testWidgets('coverage uses every song rather than only the current page', (
    tester,
  ) async {
    await pumpLocalPlaylist(tester, songsWithMissingArtwork(100, 29));

    expect(find.text('Add artwork to local music'), findsNothing);
  });

  testWidgets('open action navigates to local music settings', (tester) async {
    await pumpLocalPlaylist(tester, songsWithMissingArtwork(10, 3));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Local music settings'), findsOneWidget);
  });

  testWidgets('dismiss action persists and suppresses the prompt', (
    tester,
  ) async {
    final storage = await pumpLocalPlaylist(
      tester,
      songsWithMissingArtwork(10, 3),
    );

    await tester.tap(find.text("Don't remind me again"));
    await tester.pumpAndSettle();
    expect(storage.getBool(promptDismissedKey), isTrue);
    expect(find.text('Add artwork to local music'), findsNothing);
  });

  testWidgets('saved dismissal suppresses future prompt', (tester) async {
    await pumpLocalPlaylist(
      tester,
      songsWithMissingArtwork(10, 3),
      dismissed: true,
    );

    expect(find.text('Add artwork to local music'), findsNothing);
  });
}

class _MemoryRepository implements PlaylistRepository {
  _MemoryRepository(this.snapshot);

  final PlaylistSnapshot snapshot;

  @override
  Future<PlaylistSnapshot> load() async => snapshot;

  @override
  Future<void> save(PlaylistSnapshot value) async {}
}
