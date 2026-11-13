import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/music_source/platform/kw_source.dart';
import 'package:koyze/core/music_source/platform/wy_source.dart';
import 'package:koyze/features/player/domain/music_item.dart';

/// 记录 `getLeaderboardSongs` 被调了几次。
///
/// 分类接口曾经在返回前为每个榜拉一首歌取封面，41 个榜 × 6 路并发 = 至少
/// 7 轮请求，而榜单页给整个平台的超时只有 12 秒，几乎必然超时被当成空列表
/// ——酷我整段榜单因此消失。现在封面改由消费方按需取，这里就断言「一次都
/// 不调」，防止预取被重新加回来。
class _CountingKwSource extends KwSource {
  int songRequests = 0;

  @override
  Future<List<MusicItem>> getLeaderboardSongs(
    String leaderboardId, {
    int page = 1,
    int limit = 100,
  }) async {
    songRequests++;
    return [
      MusicItem(
        id: leaderboardId,
        name: leaderboardId,
        singer: 'Singer',
        source: 'kw',
        platform: 'kw',
        artwork: 'https://art.example/$leaderboardId.jpg',
      ),
    ];
  }
}

class _InspectableWySource extends WySource {
  _InspectableWySource({required super.dio});

  final encryptedInputs = <Map<String, dynamic>>[];

  @override
  Map<String, String> weapi(Map<String, dynamic> object) {
    encryptedInputs.add(Map<String, dynamic>.from(object));
    return const {'params': 'params', 'encSecKey': 'key'};
  }
}

void main() {
  test('Kuwo 榜单分类只返回静态表，不逐榜预取封面', () async {
    final source = _CountingKwSource();
    addTearDown(source.dispose);

    final categories = await source.getLeaderboardCategories();

    expect(categories, hasLength(41));
    // 每个榜都要能唯一定位到一个榜单，id 重复会让榜单页拿到重复条目。
    expect(categories.map((c) => c.id).toSet(), hasLength(41));
    expect(categories.every((c) => c.id.startsWith('kw:')), isTrue);

    // 关键契约：分类接口是纯本地的，一个网络请求都不发。
    expect(
      source.songRequests,
      0,
      reason: '分类不该为封面 fan-out 请求歌曲接口，否则会撑爆调用方的 12 秒超时',
    );
  });

  test('NetEase leaderboard request respects page and limit', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('playlist/detail')) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'code': 200,
                  'playlist': {
                    'trackIds': [
                      {'id': 101},
                    ],
                  },
                },
              ),
            );
            return;
          }
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'code': 200,
                'songs': [
                  {
                    'id': 101,
                    'name': 'Song',
                    'ar': [
                      {'name': 'Singer'},
                    ],
                    'al': {'name': 'Album', 'picUrl': 'https://art.example'},
                    'dt': 1000,
                  },
                ],
                'privileges': <Map<String, dynamic>>[],
              },
            ),
          );
        },
      ),
    );
    final source = _InspectableWySource(dio: dio);
    addTearDown(source.dispose);

    final songs = await source.getLeaderboardSongs(
      'wy:19723756',
      page: 3,
      limit: 1,
    );

    expect(songs.single.id, '101');
    expect(source.encryptedInputs.first['n'], 1);
    expect(source.encryptedInputs.first['p'], 3);
    expect(source.encryptedInputs.last['ids'], '[101]');
  });
}
