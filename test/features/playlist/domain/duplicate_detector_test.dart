import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/domain/duplicate_detector.dart';

MusicItem song({
  required String id,
  required String platform,
  String name = '晴天',
  String singer = '周杰伦',
  Duration duration = const Duration(seconds: 269),
  String? lyricsUrl,
  String? artwork,
}) {
  return MusicItem(
    id: id,
    name: name,
    singer: singer,
    source: platform,
    platform: platform,
    duration: duration,
    lyricsUrl: lyricsUrl,
    artwork: artwork,
  );
}

void main() {
  test('groups same title, artist and duration within 2 seconds', () {
    final wy = song(id: 'wy', platform: 'wy', lyricsUrl: 'https://lrc');
    // 时长按 2 秒一档；同一档内才算重复，269 和 270 会分到两边。
    final kw = song(
      id: 'kw',
      platform: 'kw',
      duration: const Duration(seconds: 268),
    );
    final other = song(id: 'other', platform: 'tx', name: '七里香');

    final groups = DuplicateDetector(
      songs: [wy, kw, other],
      favoriteIds: {wy.identityKey, kw.identityKey, other.identityKey},
    ).detect();

    expect(groups, hasLength(1));
    expect(groups.single.count, 2);
    expect(groups.single.songs.map((item) => item.id), containsAll(['wy', 'kw']));
  });

  test('recommends the richer copy and treats the rest as removable', () {
    final wy = song(
      id: 'wy',
      platform: 'wy',
      lyricsUrl: 'https://lrc',
      artwork: 'https://cover',
    );
    final kw = song(id: 'kw', platform: 'kw');

    final group = DuplicateDetector(
      songs: [kw, wy],
      favoriteIds: {wy.identityKey, kw.identityKey},
    ).detect().single;

    expect(group.bestSong.id, 'wy');
    expect(group.redundantSongs.map((item) => item.id), ['kw']);
  });

  test('does not group songs whose duration differs by more than 2 seconds', () {
    final first = song(id: 'a', platform: 'wy');
    final second = song(
      id: 'b',
      platform: 'kw',
      duration: const Duration(seconds: 280),
    );

    expect(
      DuplicateDetector(
        songs: [first, second],
        favoriteIds: {first.identityKey, second.identityKey},
      ).detect(),
      isEmpty,
    );
  });
}
