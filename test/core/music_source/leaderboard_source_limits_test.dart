@Tags(['live'])
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/music_source/platform/kw_source.dart';
import 'package:koyze/core/music_source/platform/wy_source.dart';
import 'package:koyze/features/player/domain/music_item.dart';

class _ConcurrencyKwSource extends KwSource {
  int active = 0;
  int maximumActive = 0;

  @override
  Future<List<MusicItem>> getLeaderboardSongs(
    String leaderboardId, {
    int page = 1,
    int limit = 100,
  }) async {
    active++;
    maximumActive = active > maximumActive ? active : maximumActive;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    active--;
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
  test('Kuwo leaderboard artwork requests use at most six workers', () async {
    final source = _ConcurrencyKwSource();
    addTearDown(source.dispose);

    final categories = await source.getLeaderboardCategories();

    expect(categories, hasLength(41));
    expect(source.maximumActive, 6);
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
