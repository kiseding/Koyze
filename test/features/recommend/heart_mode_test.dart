import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/recommend/domain/heart_mode.dart';

MusicItem _song({
  required String id,
  required String name,
  String singer = 'Aimer',
  String album = 'Sun Dance',
}) {
  return MusicItem(
    id: id,
    name: name,
    singer: singer,
    album: album,
    source: 'kw',
    platform: 'kw',
    songmid: id,
  );
}

void main() {
  group('HeartModeService', () {
    test('同歌手排在同专辑和其他结果之前', () async {
      final service = HeartModeService(
        random: Random(1),
        search: (keyword, {int limit = 40}) async {
          if (keyword == 'Aimer') {
            return [
              _song(id: '2', name: '别的专辑', album: 'Other'),
              _song(id: '1', name: '同专辑'),
            ];
          }
          if (keyword == 'Sun Dance') {
            return [_song(id: '3', name: '同专辑不同歌手', singer: 'B')];
          }
          return const [];
        },
      );
      final seed = _song(id: 'seed', name: '种子');

      final result = await service.buildRadio(seed);

      expect(result.map((s) => s.id).toList(), ['1', '2', '3']);
    });

    test('剔除种子与已在队列里的歌', () async {
      final service = HeartModeService(
        search: (keyword, {int limit = 40}) async => [
          _song(id: 'seed', name: '种子'),
          _song(id: 'queued', name: '已在队列'),
          _song(id: 'fresh', name: '新歌'),
        ],
      );

      final result = await service.buildRadio(
        _song(id: 'seed', name: '种子'),
        exclude: {_song(id: 'queued', name: '已在队列').identityKey},
      );

      expect(result.map((s) => s.id), contains('fresh'));
      expect(result.map((s) => s.id), isNot(contains('seed')));
      expect(result.every((s) => s.id != 'queued'), isTrue);
    });

    test('合唱曲目按任意一位歌手命中同歌手', () async {
      final service = HeartModeService(
        search: (keyword, {int limit = 40}) async {
          if (keyword != 'Aimer/泽野弘之') return const [];
          return [_song(id: 'x', name: '合唱', singer: '泽野弘之')];
        },
      );

      final result = await service.buildRadio(
        _song(id: 'seed', name: '种子', singer: 'Aimer/泽野弘之'),
      );

      expect(result.single.id, 'x');
    });

    test('搜索全部失败时返回空列表而不是抛错', () async {
      final service = HeartModeService(
        search: (keyword, {int limit = 40}) async =>
            throw StateError('offline'),
      );

      final result = await service.buildRadio(_song(id: 'seed', name: '种子'));

      expect(result, isEmpty);
    });

    test('结果不超过请求的数量', () async {
      final service = HeartModeService(
        random: Random(2),
        search: (keyword, {int limit = 40}) async => [
          for (var i = 0; i < 50; i++) _song(id: 's$i', name: '歌 $i'),
        ],
      );

      final result = await service.buildRadio(
        _song(id: 'seed', name: '种子'),
        size: 12,
      );

      expect(result.length, 12);
    });
  });
}
