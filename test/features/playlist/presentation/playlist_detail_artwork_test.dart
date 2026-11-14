import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/presentation/playlist_detail_screen.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';

/// 打开歌单时：行、标题、时长照常立刻显示，只有封面等到动效播完再加载。
///
/// 全量押后（列表都不建）会让内容晚一拍整体弹出来，观感更差；这里只押后封面，
/// 占位是中性底色 + 音符。
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
          artwork: 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$i.jpg',
        ),
      ),
    );
  }

  Future<void> pumpApp(WidgetTester tester, Playlist playlist) async {
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
                      builder: (_) =>
                          PlaylistDetailScreen(playlistId: playlist.id),
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
  }

  testWidgets('动效期间行照常显示，封面先用占位', (tester) async {
    await pumpApp(tester, playlistWith(30));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(ListTile), findsWidgets, reason: '列表内容不等动效');
    expect(find.text('Song 0'), findsOneWidget);
    expect(find.byType(Image), findsNothing, reason: '封面押后到动效之后');
    expect(find.byIcon(Icons.music_note_rounded), findsWidgets);

    await tester.pumpAndSettle();

    expect(find.byType(Image), findsWidgets, reason: '动效结束后开始加载封面');
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
