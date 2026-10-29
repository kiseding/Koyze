import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/data/playable_song_store.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/storage/storage_service.dart';

MusicItem _song(String id, {String source = 'tx', String? songmid}) {
  return MusicItem(
    id: id,
    name: 'Song $id',
    singer: 'Artist',
    album: 'Album',
    source: source,
    platform: source,
    songmid: songmid,
    meta: {'mid': songmid},
  );
}

Future<PlayableSongStore> _store([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(initial));
  final service = StorageService.forTesting(
    await SharedPreferences.getInstance(),
  );
  final store = PlayableSongStore(() async => service);
  await store.load();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remembers the full song so it can be resolved again', () async {
    final store = await _store();
    await store.remember(_song('1', songmid: 'mid-1'));

    final restored = store.byKey('tx', '1');
    expect(restored, isNotNull);
    expect(restored!.songmid, 'mid-1');
    expect(restored.meta?['mid'], 'mid-1');
    expect(store.length, 1);
  });

  test('keys on source and id together', () async {
    final store = await _store();
    await store.remember(_song('1', source: 'tx'));
    await store.remember(_song('1', source: 'wy'));

    expect(store.length, 2);
    expect(store.byKey('tx', '1')!.platform, 'tx');
    expect(store.byKey('wy', '1')!.platform, 'wy');
    expect(store.byKey('kw', '1'), isNull);
  });

  test('re-playing a song moves it to the newest position', () async {
    final store = await _store();
    await store.remember(_song('1'));
    await store.remember(_song('2'));
    await store.remember(_song('1'));

    expect(store.length, 2);
    // 写盘顺序即「最后播放时间」，重新播放的一首落在末尾。
    final raw = (await _storageRaw(store));
    final firstKey = raw.keys.first;
    expect(firstKey, PlayableSongStore.keyOf('tx', '2'));
  });

  test('caps the archive and drops the oldest entries', () async {
    final store = await _store();
    for (var i = 0; i < PlayableSongStore.maxEntries + 5; i++) {
      await store.remember(_song('$i'));
    }
    expect(store.length, PlayableSongStore.maxEntries);
    expect(store.byKey('tx', '0'), isNull);
    expect(store.byKey('tx', '4'), isNull);
    expect(store.byKey('tx', '5'), isNotNull);
    expect(store.byKey('tx', '${PlayableSongStore.maxEntries + 4}'), isNotNull);
  });

  test('ignores songs without an id', () async {
    final store = await _store();
    await store.remember(_song(''));
    expect(store.length, 0);
  });

  test('survives a corrupt archive', () async {
    final store = await _store({PlayableSongStore.storageKey: 'not-json{{{'});
    expect(store.length, 0);
    await store.remember(_song('1'));
    expect(store.byKey('tx', '1'), isNotNull);
  });

  test('reloads what a previous session wrote', () async {
    final first = await _store();
    await first.remember(_song('9', songmid: 'mid-9'));

    // 同一份 mock 存储，新实例：模拟下次启动。
    final prefs = await SharedPreferences.getInstance();
    final second = PlayableSongStore(
      () async => StorageService.forTesting(prefs),
    );
    await second.load();
    expect(second.byKey('tx', '9')!.songmid, 'mid-9');
  });
}

Future<Map<String, dynamic>> _storageRaw(PlayableSongStore store) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(PlayableSongStore.storageKey) ?? '{}';
  // 只关心键顺序，用正则抓出来即可。
  final keys = <String, dynamic>{};
  for (final match in RegExp(r'"([^"\\]+)":\{').allMatches(raw)) {
    keys[match.group(1)!] = true;
  }
  return keys;
}
