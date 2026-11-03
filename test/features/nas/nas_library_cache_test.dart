import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/nas/domain/nas_library_cache.dart';
import 'package:koyze/features/player/domain/music_item.dart';

MusicItem _song(String id) {
  return MusicItem(
    id: id,
    name: '歌 $id',
    singer: '歌手',
    album: '专辑',
    source: 'webdav',
    platform: 'webdav',
    artwork: 'http://nas.local/$id.jpg',
    songmid: 'http://nas.local/$id.flac',
    meta: {
      'folder': '歌手/专辑',
      'lyricUrl': 'http://nas.local/$id.lrc',
      'suffix': 'flac',
    },
  );
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nas_cache_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  NasLibraryCache cache() =>
      NasLibraryCache(serverId: 'webdav', directory: () async => root);

  test('round-trips songs and keeps metadata', () async {
    await cache().write([_song('a'), _song('b')]);

    final snapshot = await cache().read();

    expect(snapshot, isNotNull);
    expect(snapshot!.songs, hasLength(2));
    final first = snapshot.songs.first;
    expect(first.name, '歌 a');
    expect(first.artwork, contains('a.jpg'));
    expect(first.meta?['lyricUrl'], contains('a.lrc'));
    expect(first.meta?['folder'], '歌手/专辑');
    expect(snapshot.age.inSeconds, lessThan(5));
  });

  test('returns null when nothing was written', () async {
    expect(await cache().read(), isNull);
  });

  test('ignores a corrupted file instead of throwing', () async {
    await File('${root.path}/webdav.json').writeAsString('{"version":1,');

    expect(await cache().read(), isNull);
  });

  test('ignores a snapshot from another schema version', () async {
    await File('${root.path}/webdav.json').writeAsString(
      '{"version":99,"savedAt":0,"songs":[{"id":"a","name":"a","source":"webdav","platform":"webdav"}]}',
    );

    expect(await cache().read(), isNull);
  });

  test('clear removes the snapshot', () async {
    await cache().write([_song('a')]);
    await cache().clear();

    expect(await cache().read(), isNull);
  });
}
