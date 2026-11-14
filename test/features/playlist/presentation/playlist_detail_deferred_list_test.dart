import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/presentation/playlist_detail_screen.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';

/// 歌单详情页的重内容（首屏列表）必须等展开动效播完再挂载。
///
/// 反例代价很大：列表首帧一旦进了动效窗口，长歌单会在展开时明显顿住
/// —— 首屏十几行 + 十几张封面全在那一帧里建。
void main() {
  Playlist playlistWith(int count) {
    final now = DateTime.utc(2026);
    return Playlist(
      id: 'big',
      name: 'Big',
      createdAt: now,
      updatedAt: now,
      songs: List.generate(
        count,
        (i) => MusicItem(
          id: 'song-$i',
          name: 'Song $i',
          singer: 'Artist $i',
          source: 'kw',
        ),
      ),
    );
  }

  Future<ProviderContainer> pumpApp(
    WidgetTester tester,
    Playlist playlist, {
    String? focusSongId,
  }) async {
    final container = ProviderContainer(
      overrides: [
        playlistRepositoryProvider.overrideWithValue(
          _MemoryRepository(
            PlaylistSnapshot(schemaVersion: 1, playlists: [playlist]),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(playlistServiceProvider).init();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlaylistDetailScreen(
                        playlistId: playlist.id,
                        focusSongId: focusSongId,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('展开动效期间不建首屏列表，动效结束后才出现', (tester) async {
    await pumpApp(tester, playlistWith(30));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byType(ListTile),
      findsNothing,
      reason: '动效还在播，列表首帧不能进动效窗口',
    );

    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsWidgets);
    expect(find.text('Song 0'), findsOneWidget);
  });

  testWidgets('推迟挂载后仍能定位到指定歌曲', (tester) async {
    await pumpApp(tester, playlistWith(60), focusSongId: 'song-40');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final scrollable = tester.widget<Scrollable>(
      find.byType(Scrollable).first,
    );
    expect(
      scrollable.controller?.offset ?? 0,
      greaterThan(0),
      reason: '列表挂载晚了，帧末补做的那次定位必须补上',
    );
  });
}

class _MemoryRepository implements PlaylistRepository {
  _MemoryRepository(this.snapshot);

  PlaylistSnapshot snapshot;

  @override
  Future<PlaylistSnapshot> load() async => snapshot;

  @override
  Future<void> save(PlaylistSnapshot value) async => snapshot = value;
}
