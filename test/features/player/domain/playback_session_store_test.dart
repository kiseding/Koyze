import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/domain/playback_session.dart';
import 'package:koyze/features/player/domain/playback_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MusicItem song(String id) => MusicItem(
    id: id,
    name: 'Song $id',
    singer: 'Singer',
    source: 'tx',
    platform: 'tx',
  );

  test('unchanged queue context is persisted only once', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final writes = <String, int>{};
    final storage = StorageService.forTesting(
      preferences,
      writeOverride: (operation, key, value) async {
        writes.update(key, (count) => count + 1, ifAbsent: () => 1);
        return switch (operation) {
          'setString' => preferences.setString(key, value! as String),
          'remove' => preferences.remove(key),
          _ => false,
        };
      },
    );
    final store = PlaybackSessionStore(() async => storage);
    final queue = [song('a'), song('b')];

    await store.save(
      PlaybackSession(startIndex: 0, song: queue[0], queue: queue),
    );
    await store.save(
      PlaybackSession(startIndex: 1, song: queue[1], queue: queue),
    );

    expect(writes['playback_session_context_v2'], 1);
    expect(writes['playback_session_current_v2'], 2);
    final loaded = await store.load();
    expect(loaded?.startIndex, 1);
    expect(loaded?.song.id, 'b');
    expect(loaded?.queue.map((item) => item.id), ['a', 'b']);
  });

  test('mismatched context falls back to the current song', () async {
    SharedPreferences.setMockInitialValues({
      'playback_session_context_v2':
          '{"playlistId":null,"queue":[{"id":"stale"}]}',
      'playback_session_current_v2':
          '{"contextHash":"different","startIndex":4,'
          '"song":{"id":"current","name":"Current",'
          '"singer":"Singer","source":"tx"}}',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = PlaybackSessionStore(
      () async => StorageService.forTesting(preferences),
    );

    final loaded = await store.load();

    expect(loaded?.song.id, 'current');
    expect(loaded?.queue, isEmpty);
  });

  test('legacy session remains readable', () async {
    final legacy = PlaybackSession(
      startIndex: 0,
      song: song('legacy'),
      queue: [song('legacy')],
    );
    SharedPreferences.setMockInitialValues({
      'playback_session_v1': jsonEncode(legacy.toJson()),
    });
    final preferences = await SharedPreferences.getInstance();
    final store = PlaybackSessionStore(
      () async => StorageService.forTesting(preferences),
    );

    final loaded = await store.load();

    expect(loaded?.song.id, 'legacy');
    expect(loaded?.queue.single.id, 'legacy');
  });

  test('signed media URLs are removed from durable session state', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = StorageService.forTesting(preferences);
    final store = PlaybackSessionStore(() async => storage);
    final signed = MusicItem(
      id: 'signed',
      name: 'Signed',
      singer: 'Singer',
      source: 'custom-source',
      platform: 'tx',
      url: 'https://media.example/play?token=private',
      lyricsUrl: 'https://media.example/lyric?signature=private',
      meta: {
        'musicUrl': 'https://media.example/nested?key=private',
        'albumId': 'safe',
      },
    );

    await store.save(
      PlaybackSession(startIndex: 0, song: signed, queue: [signed]),
    );

    final persisted = preferences.getString('playback_session_context_v2')!;
    expect(persisted, isNot(contains('media.example')));
    expect(persisted, isNot(contains('private')));
    expect(persisted, contains('albumId'));
    final loaded = await store.load();
    expect(loaded?.song.url, isNull);
    expect(loaded?.queue.single.meta, {'albumId': 'safe'});
  });

  test('stale persisted URLs are sanitized and rewritten on load', () async {
    final stale = PlaybackSession(
      startIndex: 0,
      song: MusicItem(
        id: 'stale',
        name: 'Stale',
        singer: 'Singer',
        source: 'custom-source',
        platform: 'tx',
        url: 'https://media.example/play?token=private',
        meta: {'playUrl': 'https://media.example/other?token=private'},
      ),
    );
    SharedPreferences.setMockInitialValues({
      'playback_session_v1': jsonEncode(stale.toJson()),
    });
    final preferences = await SharedPreferences.getInstance();
    final store = PlaybackSessionStore(
      () async => StorageService.forTesting(preferences),
    );

    final loaded = await store.load();

    expect(loaded?.song.url, isNull);
    expect(loaded?.song.meta, isEmpty);
    expect(preferences.getString('playback_session_v1'), isNull);
    expect(
      preferences.getString('playback_session_current_v2'),
      isNot(contains('media.example')),
    );
  });
}
