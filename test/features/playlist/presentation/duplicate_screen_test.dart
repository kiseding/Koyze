import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/presentation/duplicate_screen.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';

MusicItem _song({
  required String id,
  required String platform,
  String name = '晴天',
  String singer = '周杰伦',
  String? lyricsUrl,
}) {
  return MusicItem(
    id: id,
    name: name,
    singer: singer,
    source: platform,
    platform: platform,
    duration: const Duration(seconds: 269),
    lyricsUrl: lyricsUrl,
  );
}

PlaylistSnapshot _snapshot(List<MusicItem> favorites) {
  final now = DateTime.utc(2026);
  return PlaylistSnapshot(
    schemaVersion: 1,
    playlists: [
      Playlist(
        id: 'favorites',
        name: 'Favorites',
        songs: favorites,
        createdAt: now,
        updatedAt: now,
      ),
      Playlist(id: 'recent', name: 'Recent', createdAt: now, updatedAt: now),
      Playlist(id: 'local', name: 'Local', createdAt: now, updatedAt: now),
    ],
  );
}

void main() {
  test('duplicate screen lets the user pick which copies to remove', () {
    final source = File(
      'lib/features/playlist/presentation/duplicate_screen.dart',
    ).readAsStringSync();

    expect(source, contains('Checkbox('));
    expect(source, contains('勾选要移除的'));
    expect(source, contains('移除已选'));
    expect(source, contains('按推荐勾选'));
    expect(source, contains('_toggleSelected'));
    expect(source, isNot(contains('一键移除')));
    expect(source, isNot(contains('移除其余版本')));
    expect(source, isNot(contains('onLongPress')));
  });

  test('settings no longer owns the duplicate songs entry', () {
    final settings = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();
    expect(settings, isNot(contains('重复歌曲')));
    expect(settings, isNot(contains('/duplicates')));
    expect(settings, isNot(contains("_buildSection(context, '歌单'")));

    final homeQuick = File(
      'lib/features/home/presentation/home_quick_provider.dart',
    ).readAsStringSync();
    expect(homeQuick, isNot(contains("id: 'duplicates'")));
    expect(homeQuick, isNot(contains('重复歌曲')));
  });

  testWidgets('each duplicate copy is checkable and defaults to recommended', (
    tester,
  ) async {
    final wy = _song(id: 'wy', platform: 'wy', lyricsUrl: 'https://lrc');
    final kw = _song(id: 'kw', platform: 'kw');
    final repository = _MemoryRepository(_snapshot([wy, kw]));
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(playlistServiceProvider).init();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DuplicateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('勾选要移除的'), findsOneWidget);
    expect(find.text('推荐保留'), findsOneWidget);
    expect(find.text('移除已选'), findsOneWidget);
    expect(find.text('一键移除'), findsNothing);

    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes, hasLength(2));
    expect(boxes.where((box) => box.value == true), hasLength(1));
    expect(boxes.where((box) => box.value == false), hasLength(1));

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();

    final toggled = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .map((box) => box.value)
        .toList();
    expect(toggled, isNot(equals([false, true])));
    expect(toggled.where((value) => value == true).length, 1);
  });

  testWidgets('removing selected copies keeps the unchecked favorite', (
    tester,
  ) async {
    final wy = _song(id: 'wy', platform: 'wy', lyricsUrl: 'https://lrc');
    final kw = _song(id: 'kw', platform: 'kw');
    final repository = _MemoryRepository(_snapshot([wy, kw]));
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final service = container.read(playlistServiceProvider);
    await service.init();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DuplicateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('移除已选'));
    await tester.pumpAndSettle();

    final remaining = await service.getAllSongs('favorites');
    expect(remaining.map((song) => song.id), ['wy']);
    expect(find.text('收藏列表没有重复歌曲'), findsOneWidget);
  });
}

final class _MemoryRepository implements PlaylistRepository {
  _MemoryRepository(this.snapshot);

  PlaylistSnapshot snapshot;

  @override
  Future<PlaylistSnapshot> load() async => snapshot;

  @override
  Future<void> save(PlaylistSnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}
