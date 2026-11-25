import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/network/music_source_service.dart';
import 'package:koyze/core/network/play_url_result.dart';
import 'package:koyze/core/music_source/platform/built_in_source_manager.dart';
import 'package:koyze/core/music_source/platform/music_platform.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/lyric/domain/lyric.dart';
import 'package:koyze/features/player/domain/music_item.dart';

class _FakeCustomSourceService extends CustomSourceService {
  _FakeCustomSourceService(this.sources, this.loader);

  final List<CustomSource> sources;
  final Future<String?> Function(String sourceId, MusicItem music) loader;

  @override
  List<CustomSource> get enabledSources => sources;

  @override
  Future<String?> getLyric(String sourceId, MusicItem music) =>
      loader(sourceId, music);
}

class _LyricPlatform extends MusicPlatform {
  _LyricPlatform(this.lyric, {this.payload});

  final String lyric;
  final LyricPayload? payload;

  @override
  String get id => 'tx';

  @override
  String get name => 'TX';

  @override
  Future<String?> getLyric(MusicItem music) async => lyric;

  @override
  Future<LyricPayload?> getLyricPayload(MusicItem music) async =>
      payload ?? await super.getLyricPayload(music);

  @override
  MusicItem parseItem(Map<String, dynamic> raw, String source) => MusicItem(
    id: raw['id']?.toString() ?? '',
    name: raw['name']?.toString() ?? '',
    singer: raw['singer']?.toString() ?? '',
    source: source,
    platform: id,
  );

  @override
  Future<List<MusicItem>> search(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async => [];
}

class _SearchPlatform extends MusicPlatform {
  _SearchPlatform({
    required this.platformId,
    this.results = const [],
    this.lyric,
  });

  final String platformId;
  final List<MusicItem> results;
  final String? lyric;

  @override
  String get id => platformId;

  @override
  String get name => platformId;

  @override
  Future<List<MusicItem>> search(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async => results;

  @override
  Future<String?> getLyric(MusicItem music) async => lyric;

  @override
  MusicItem parseItem(Map<String, dynamic> raw, String source) => MusicItem(
    id: raw['id']?.toString() ?? '',
    name: raw['name']?.toString() ?? '',
    singer: raw['singer']?.toString() ?? '',
    source: source,
    platform: id,
  );
}

class _TrackingSearchPlatform extends _SearchPlatform {
  _TrackingSearchPlatform(String platformId, this.searched, {super.results})
    : super(platformId: platformId);

  final List<String> searched;

  @override
  Future<List<MusicItem>> search(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async {
    searched.add(platformId);
    return super.search(keyword, page: page, limit: limit);
  }
}

CustomSource _source(String id) {
  final now = DateTime.utc(2026);
  return CustomSource(
    id: id,
    name: id,
    description: '',
    version: '1',
    author: 'test',
    script: '/* source */',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final item = MusicItem(
    id: 'song-1',
    name: 'Song',
    singer: 'Singer',
    duration: const Duration(minutes: 3),
    platform: 'tx',
    source: 'tx',
  );

  PlayUrlResult playable(String quality, {String? actual}) => PlayUrlResult(
    url: 'https://media.example/$quality.mp3',
    requestedQuality: quality,
    actualQuality: actual ?? quality,
    platform: 'tx',
  );

  test(
    'playback fallback uses target identity and rejects ambiguous matches',
    () async {
      final target = item.copyWith(id: 'qq-catalog-id', songmid: 'qq-mid');
      final original = item.copyWith(id: 'kg-id', source: 'kg', platform: 'kg');
      final results = [
        target.copyWith(
          id: 'live',
          songmid: 'live',
          duration: const Duration(minutes: 4),
        ),
        target.copyWith(id: 'cover', songmid: 'cover', singer: 'Singer Cover'),
        target,
      ];
      final service = MusicSourceService(
        CustomSourceService(),
        builtInSources: BuiltInSourceManager(
          platforms: [_SearchPlatform(platformId: 'tx', results: results)],
        ),
      );
      expect(
        await service.matchPlaybackFallback(original, 'tx', null),
        same(target),
      );
      results.add(target.copyWith(id: 'other', songmid: 'other'));
      expect(await service.matchPlaybackFallback(original, 'tx', null), isNull);
    },
  );

  test('unknown platform is not remapped to another platform', () {
    final service = MusicSourceService(CustomSourceService());

    expect(
      service.resolvePlatform(
        MusicItem(
          id: 'unknown',
          name: 'Song',
          singer: 'Singer',
          platform: 'custom',
          source: 'custom',
        ),
      ),
      isEmpty,
    );
    expect(
      service.resolvePlatform(
        MusicItem(
          id: 'kg',
          name: 'Song',
          singer: 'Singer',
          platform: 'kg',
          source: 'kg',
        ),
      ),
      'kg',
    );
  });

  test('known platform lyrics prefer built-in word timing', () async {
    const qrc = '[0,1000]逐(0,500)字(500,500)';
    final service = MusicSourceService(
      CustomSourceService(),
      builtInSources: BuiltInSourceManager(platforms: [_LyricPlatform(qrc)]),
    );

    expect(await service.getLyric(item), qrc);
  });

  test(
    'parallel lyrics prefer word timing and retain selected translation',
    () async {
      final custom = _FakeCustomSourceService([
        _source('custom'),
      ], (_, _) async => '[00:01.00]普通歌词');
      final service = MusicSourceService(
        custom,
        builtInSources: BuiltInSourceManager(
          platforms: [
            _LyricPlatform(
              '',
              payload: const LyricPayload(
                main: '[00:01.00]<0,200>逐<200,200>字',
                translation: '[00:01.00]translated',
              ),
            ),
          ],
        ),
      );

      final payload = await service.getLyricPayload(item);

      expect(payload?.main, '[00:01.00]<0,200>逐<200,200>字');
      expect(payload?.translation, '[00:01.00]translated');
    },
  );

  test(
    'same-quality lyric candidates preserve built-in source priority',
    () async {
      final custom = _FakeCustomSourceService([
        _source('custom'),
      ], (_, _) async => '[00:01.00]自定义普通歌词');
      final service = MusicSourceService(
        custom,
        builtInSources: BuiltInSourceManager(
          platforms: [_LyricPlatform('[00:01.00]内置普通歌词')],
        ),
      );

      final payload = await service.getLyricPayload(item);

      expect(payload?.main, '[00:01.00]内置普通歌词');
    },
  );

  test('custom lyric timeout is isolated from built-in candidate', () async {
    final custom = _FakeCustomSourceService([
      _source('slow'),
    ], (_, _) => Completer<String?>().future);
    final service = MusicSourceService(
      custom,
      lyricSourceTimeout: const Duration(milliseconds: 10),
      builtInSources: BuiltInSourceManager(
        platforms: [_LyricPlatform('[00:01.00]内置歌词')],
      ),
    );

    final payload = await service.getLyricPayload(item);

    expect(payload?.main, '[00:01.00]内置歌词');
  });

  test('cross-platform word-timed lyric beats current plain lyric', () async {
    final kwSong = item.copyWith(id: 'kw-1', platform: 'kw', source: 'kw');
    final service = MusicSourceService(
      CustomSourceService(),
      builtInSources: BuiltInSourceManager(
        platforms: [
          _LyricPlatform('[00:01.00]普通歌词'),
          _SearchPlatform(
            platformId: 'kw',
            results: [kwSong],
            lyric: '[00:01.00]<0,200>逐<200,200>字',
          ),
        ],
      ),
    );

    final payload = await service.getLyricPayload(item);

    expect(payload?.main, '[00:01.00]<0,200>逐<200,200>字');
  });

  test('custom source keeps an HTTP media URL unchanged', () async {
    final service = MusicSourceService(
      CustomSourceService(),
      hasEnabledCustomSources: () => true,
      customQualityResolver: (music, quality, cancelToken) async {
        return PlayUrlResult(
          url: 'http://media.example.test/song.mp3?token=signature',
          requestedQuality: quality,
          actualQuality: quality,
          platform: 'tx',
        );
      },
    );

    final result = await service.resolvePlayableUrl(
      item,
      preferredQuality: '320k',
    );

    expect(result?.url, 'http://media.example.test/song.mp3?token=signature');
  });

  test(
    'failed custom platform falls back through a matching platform result',
    () async {
      final kwSong = MusicItem(
        id: 'kw-1',
        name: 'Song',
        singer: 'Singer',
        duration: const Duration(minutes: 3),
        source: 'kw',
        platform: 'kw',
        songmid: 'kw-1',
      );
      final service = MusicSourceService(
        CustomSourceService(),
        hasEnabledCustomSources: () => true,
        enabledCustomSourceIds: () => ['source'],
        customSourceQualityResolver:
            (sourceId, music, quality, cancelToken) async {
              if (music.platform == 'kw') {
                return PlayUrlResult(
                  url: playable(quality).url,
                  requestedQuality: quality,
                  actualQuality: quality,
                  platform: 'kw',
                );
              }
              return null;
            },
        builtInSources: BuiltInSourceManager(
          platforms: [
            _SearchPlatform(platformId: 'tx'),
            _SearchPlatform(platformId: 'kw', results: [kwSong]),
          ],
        ),
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: '320k',
      );

      expect(result?.platform, 'kw');
      expect(result?.url, contains('/320k.mp3'));
    },
  );

  test(
    'incomplete imported metadata is refreshed for the enabled source',
    () async {
      final refreshedSong = MusicItem(
        id: 'song-1',
        name: 'Song',
        singer: 'Singer',
        source: 'tx',
        platform: 'tx',
        songmid: 'song-1',
        meta: const {'strMediaMid': 'media-1'},
      );
      final service = MusicSourceService(
        CustomSourceService(),
        hasEnabledCustomSources: () => true,
        customQualityResolver: (music, quality, cancelToken) async {
          if (music.meta?['strMediaMid'] != 'media-1') return null;
          return playable(quality);
        },
        builtInSources: BuiltInSourceManager(
          platforms: [
            _SearchPlatform(platformId: 'tx', results: [refreshedSong]),
          ],
        ),
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: '320k',
      );

      expect(result?.url, 'https://media.example/320k.mp3');
      expect(result?.platform, 'tx');
      expect(result?.fromCustomSource, isTrue);
    },
  );

  test('automatic fallback searches every built-in platform', () async {
    final searched = <String>[];
    final kgSong = MusicItem(
      id: 'kg-1',
      name: 'Song',
      singer: 'Singer',
      source: 'kg',
      platform: 'kg',
    );
    final service = MusicSourceService(
      CustomSourceService(),
      hasEnabledCustomSources: () => true,
      customQualityResolver: (music, quality, cancelToken) async => null,
      builtInSources: BuiltInSourceManager(
        platforms: [
          _TrackingSearchPlatform('tx', searched),
          _TrackingSearchPlatform('kg', searched, results: [kgSong]),
          _TrackingSearchPlatform('kw', searched),
          _TrackingSearchPlatform('wy', searched),
        ],
      ),
    );

    expect(
      await service.resolvePlayableUrl(
        item,
        preferredQuality: '320k',
        allowSamePlatformRefresh: false,
      ),
      isNull,
    );
    expect(searched, ['kw', 'wy', 'kg']);
  });

  test(
    'resolved result reports the platform actually being resolved',
    () async {
      final kwSong = MusicItem(
        id: 'kw-1',
        name: 'Song',
        singer: 'Singer',
        duration: const Duration(minutes: 3),
        source: 'kw',
        platform: 'kw',
      );
      final service = MusicSourceService(
        CustomSourceService(),
        hasEnabledCustomSources: () => true,
        customQualityResolver: (music, quality, cancelToken) async {
          if (music.platform != 'kw') return null;
          return PlayUrlResult(
            url: 'https://media.example/kw.mp3',
            requestedQuality: quality,
            actualQuality: quality,
            platform: 'tx',
          );
        },
        builtInSources: BuiltInSourceManager(
          platforms: [
            _SearchPlatform(platformId: 'tx'),
            _SearchPlatform(platformId: 'kw', results: [kwSong]),
          ],
        ),
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: '320k',
      );

      expect(result?.platform, 'kw');
    },
  );

  test('lyrics fall back by matching the song on another platform', () async {
    const lyric = '[0,1000]逐(0,500)字(500,500)';
    final kwSong = MusicItem(
      id: 'kw-1',
      name: 'Song',
      singer: 'Singer',
      source: 'kw',
      platform: 'kw',
      songmid: 'kw-1',
    );
    final service = MusicSourceService(
      CustomSourceService(),
      builtInSources: BuiltInSourceManager(
        platforms: [
          _SearchPlatform(platformId: 'tx'),
          _SearchPlatform(platformId: 'kw', results: [kwSong], lyric: lyric),
        ],
      ),
    );

    expect(await service.getLyric(item), lyric);
  });

  test(
    'each quality is attempted once and actual downgrade is reported',
    () async {
      final calls = <String>[];
      final service = MusicSourceService(
        CustomSourceService(),
        hasEnabledCustomSources: () => true,
        customQualityResolver: (music, quality, cancelToken) async {
          calls.add(quality);
          return quality == '320k' ? playable(quality) : null;
        },
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: 'flac',
      );

      expect(calls, ['flac', '320k']);
      expect(result?.requestedQuality, 'flac');
      expect(result?.actualQuality, '320k');
    },
  );

  test(
    'uses a playable custom downgrade without requesting lower qualities',
    () async {
      final calls = <String>[];
      final service = MusicSourceService(
        CustomSourceService(),
        hasEnabledCustomSources: () => true,
        customQualityResolver: (music, quality, cancelToken) async {
          calls.add(quality);
          if (quality == 'flac') return playable(quality, actual: '128k');
          return null;
        },
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: 'flac',
      );

      expect(calls, ['flac']);
      expect(result?.requestedQuality, 'flac');
      expect(result?.actualQuality, '128k');
    },
  );

  test(
    'custom downgrade stops before repeating at lower request qualities',
    () async {
      final calls = <String>[];
      final service = MusicSourceService(
        CustomSourceService(),
        hasEnabledCustomSources: () => true,
        customQualityResolver: (music, quality, cancelToken) async {
          calls.add(quality);
          return playable(quality, actual: '128k');
        },
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: 'flac',
      );

      expect(calls, ['flac']);
      expect(result?.requestedQuality, 'flac');
      expect(result?.actualQuality, '128k');
    },
  );

  test('returns null when every enabled source fails', () async {
    final service = MusicSourceService(
      CustomSourceService(),
      hasEnabledCustomSources: () => true,
      customQualityResolver: (music, quality, cancelToken) async => null,
      builtInSources: BuiltInSourceManager(platforms: const []),
    );

    final result = await service.resolvePlayableUrl(
      item,
      preferredQuality: '320k',
    );

    expect(result, isNull);
  });

  test('successful custom source is used directly', () async {
    final service = MusicSourceService(
      CustomSourceService(),
      hasEnabledCustomSources: () => true,
      customQualityResolver: (music, quality, cancelToken) async =>
          playable(quality),
    );

    final result = await service.resolvePlayableUrl(
      item,
      preferredQuality: '320k',
    );

    expect(result?.url, 'https://media.example/320k.mp3');
    expect(result?.fromCustomSource, isTrue);
  });

  test('cancellation stops fallback before another quality attempt', () async {
    final calls = <String>[];
    final token = CancelToken();
    final service = MusicSourceService(
      CustomSourceService(),
      hasEnabledCustomSources: () => true,
      customQualityResolver: (music, quality, cancelToken) async {
        calls.add(quality);
        token.cancel('stop');
        return null;
      },
    );

    await expectLater(
      service.resolvePlayableUrl(
        item,
        preferredQuality: 'flac',
        cancelToken: token,
      ),
      throwsA(
        isA<DioException>().having(CancelToken.isCancel, 'cancelled', true),
      ),
    );
    expect(calls, ['flac']);
  });

  test(
    'later custom source exact result beats earlier provisional result',
    () async {
      final calls = <String>[];
      final service = MusicSourceService(
        CustomSourceService(),
        enabledCustomSourceIds: () => ['A', 'B'],
        customSourceQualityResolver:
            (sourceId, music, quality, cancelToken) async {
              calls.add('$sourceId:$quality');
              return sourceId == 'A'
                  ? playable(quality, actual: '128k')
                  : playable(quality);
            },
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: 'flac',
      );

      expect(calls, ['A:flac', 'B:flac']);
      expect(result?.actualQuality, 'flac');
      expect(result?.requestedQuality, 'flac');
    },
  );

  test(
    'best provisional result improves by actual quality across sources',
    () async {
      final service = MusicSourceService(
        CustomSourceService(),
        enabledCustomSourceIds: () => ['A', 'B'],
        customSourceQualityResolver:
            (sourceId, music, quality, cancelToken) async {
              if (quality != 'flac') return null;
              return sourceId == 'A'
                  ? playable(quality, actual: '128k')
                  : playable(quality, actual: '192k');
            },
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: 'flac',
      );

      expect(result?.actualQuality, '192k');
      expect(result?.requestedQuality, 'flac');
    },
  );

  test('equal provisional quality keeps earlier source priority', () async {
    final service = MusicSourceService(
      CustomSourceService(),
      enabledCustomSourceIds: () => ['A', 'B'],
      customSourceQualityResolver:
          (sourceId, music, quality, cancelToken) async {
            if (quality != 'flac') return null;
            return PlayUrlResult(
              url: 'https://media.example/$sourceId.mp3',
              requestedQuality: quality,
              actualQuality: '128k',
              platform: 'tx',
            );
          },
    );

    final result = await service.resolvePlayableUrl(
      item,
      preferredQuality: 'flac',
    );

    expect(result?.url, 'https://media.example/A.mp3');
  });

  test(
    'higher provisional actual quality beats later exact candidate',
    () async {
      final service = MusicSourceService(
        CustomSourceService(),
        hasEnabledCustomSources: () => true,
        customQualityResolver: (music, quality, cancelToken) async {
          if (quality == 'hires') return playable(quality, actual: 'flac');
          if (quality == '320k') return playable(quality);
          return null;
        },
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: 'hires',
      );

      expect(result?.actualQuality, 'flac');
      expect(result?.requestedQuality, 'hires');
    },
  );

  test('first playable custom downgrade is used immediately', () async {
    final service = MusicSourceService(
      CustomSourceService(),
      hasEnabledCustomSources: () => true,
      customQualityResolver: (music, quality, cancelToken) async {
        if (quality == 'flac') return playable(quality, actual: '128k');
        if (quality == '320k') return playable(quality, actual: '192k');
        return null;
      },
    );

    final result = await service.resolvePlayableUrl(
      item,
      preferredQuality: 'flac',
    );

    expect(result?.actualQuality, '128k');
    expect(result?.requestedQuality, 'flac');
    expect(result?.fromCustomSource, isTrue);
  });

  test('custom sources compare results within the requested quality', () async {
    final calls = <String>[];
    final service = MusicSourceService(
      CustomSourceService(),
      enabledCustomSourceIds: () => ['A', 'B'],
      customSourceQualityResolver:
          (sourceId, music, quality, cancelToken) async {
            calls.add('$sourceId:$quality');
            if (sourceId == 'B' && quality == 'flac') {
              return playable(quality, actual: '192k');
            }
            if (sourceId == 'A' && quality == 'flac') {
              return playable(quality, actual: '192k');
            }
            return null;
          },
    );

    final result = await service.resolvePlayableUrl(
      item,
      preferredQuality: 'flac',
    );

    expect(result?.url, 'https://media.example/flac.mp3');
    expect(result?.actualQuality, '192k');
    expect(result?.requestedQuality, 'flac');
    expect(calls, ['A:flac', 'B:flac']);
  });

  test('inverse cross-candidate tie still follows source priority', () async {
    final service = MusicSourceService(
      CustomSourceService(),
      enabledCustomSourceIds: () => ['A', 'B'],
      customSourceQualityResolver:
          (sourceId, music, quality, cancelToken) async {
            if (sourceId == 'A' && quality == 'flac') {
              return playable(quality, actual: '192k');
            }
            if (sourceId == 'B' && quality == '320k') {
              return playable(quality, actual: '192k');
            }
            return null;
          },
    );

    final result = await service.resolvePlayableUrl(
      item,
      preferredQuality: 'flac',
    );

    expect(result?.url, 'https://media.example/flac.mp3');
    expect(result?.actualQuality, '192k');
  });

  test(
    'honest early source success does not query lower-priority source',
    () async {
      final calls = <String>[];
      final service = MusicSourceService(
        CustomSourceService(),
        enabledCustomSourceIds: () => ['A', 'B'],
        customSourceQualityResolver:
            (sourceId, music, quality, cancelToken) async {
              calls.add('$sourceId:$quality');
              return sourceId == 'A' && quality == 'flac'
                  ? playable(quality)
                  : null;
            },
      );

      final result = await service.resolvePlayableUrl(
        item,
        preferredQuality: 'flac',
      );

      expect(result?.actualQuality, 'flac');
      expect(calls, ['A:flac']);
    },
  );

  test('no enabled source returns null without searching', () async {
    final searched = <String>[];
    final service = MusicSourceService(
      CustomSourceService(),
      builtInSources: BuiltInSourceManager(
        platforms: [
          _TrackingSearchPlatform('tx', searched),
          _TrackingSearchPlatform('kw', searched),
        ],
      ),
    );

    expect(
      await service.resolvePlayableUrl(item, preferredQuality: '320k'),
      isNull,
    );
    expect(searched, isEmpty);
    expect(service.hasEnabledCustomSource, isFalse);
  });

  test('overall playback URL timeout cancels the active resolution', () async {
    final cancelToken = CancelToken();
    final service = MusicSourceService(
      CustomSourceService(),
      hasEnabledCustomSources: () => true,
      customQualityResolver: (music, quality, token) =>
          Completer<PlayUrlResult?>().future,
      playUrlResolutionTimeout: const Duration(milliseconds: 20),
    );

    final result = await service.resolvePlayableUrl(
      item,
      preferredQuality: 'flac',
      cancelToken: cancelToken,
    );

    expect(result, isNull);
    expect(cancelToken.isCancelled, isTrue);
  });
}
