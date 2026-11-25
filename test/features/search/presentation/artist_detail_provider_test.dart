import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/search/domain/artist_songs.dart';

void main() {
  test(
    'matches a split collaboration artist exactly and skips other tracks',
    () {
      final songs = [
        MusicItem(
          id: '1',
          name: '合作曲',
          singer: '歌手甲 feat. 歌手乙',
          source: 'tx',
          platform: 'tx',
        ),
        MusicItem(
          id: '2',
          name: '相似名称',
          singer: '歌手乙乐队',
          source: 'tx',
          platform: 'tx',
        ),
        MusicItem(
          id: '3',
          name: '歌单结果',
          singer: '歌手乙',
          source: 'tx',
          platform: 'tx',
          isPlayable: false,
        ),
      ];

      expect(songsForArtist(songs, '歌手乙').map((song) => song.id), ['1']);
    },
  );
}
