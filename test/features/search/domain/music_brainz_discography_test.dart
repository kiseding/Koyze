import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/search/domain/music_brainz_discography.dart';

/// 用拦截器伪造 MusicBrainz 响应，并记录请求顺序。
Dio _fakeDio(
  Map<String, dynamic> Function(RequestOptions options, int index) handler, {
  List<RequestOptions>? seen,
}) {
  final dio = Dio();
  var index = 0;
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, interceptor) {
        seen?.add(options);
        interceptor.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: handler(options, index++),
          ),
        );
      },
    ),
  );
  return dio;
}

Map<String, dynamic> _artistSearch(
  String name, {
  int score = 100,
  String id = 'mbid-1',
}) => {
  'artists': [
    {'id': id, 'name': name, 'score': score},
  ],
};

Map<String, dynamic> _releaseGroups(List<Map<String, dynamic>> groups) => {
  'release-groups': groups,
};

MusicItem _song(String name, String album, {Map<String, dynamic>? meta}) =>
    MusicItem(
      id: name,
      name: name,
      singer: '歌手',
      album: album,
      source: 'tx',
      platform: 'tx',
      meta: meta,
    );

void main() {
  group('applyMusicBrainzReleaseDates', () {
    test('fills the year for an exactly matching album only', () {
      final songs = [
        _song('a', '叶惠美'),
        _song('b', '七里香'),
        _song('c', '不存在的专辑'),
      ];
      final result = applyMusicBrainzReleaseDates(songs, const [
        MusicBrainzRelease(title: '叶惠美', firstReleaseDate: '2003-07-31'),
        MusicBrainzRelease(title: '七里香', firstReleaseDate: '2004'),
      ]);

      expect(result[0].meta?['musicBrainzReleaseDate'], '2003-07-31');
      expect(result[1].meta?['musicBrainzReleaseDate'], '2004');
      expect(result[2].meta, isNull);
    });

    test('ignores punctuation and spacing differences in album names', () {
      final result = applyMusicBrainzReleaseDates(
        [_song('a', 'Sgt. Pepper’s Lonely Hearts Club Band')],
        const [
          MusicBrainzRelease(
            title: 'Sgt Pepper’s Lonely Hearts Club Band',
            firstReleaseDate: '1967-06-01',
          ),
        ],
      );

      expect(result.single.meta?['musicBrainzReleaseDate'], '1967-06-01');
    });

    test('keeps the earliest date when several releases share a title', () {
      final result = applyMusicBrainzReleaseDates(
        [_song('a', 'Album')],
        const [
          MusicBrainzRelease(title: 'Album', firstReleaseDate: '2011-09-02'),
          MusicBrainzRelease(title: 'Album', firstReleaseDate: '2009-01-05'),
        ],
      );

      expect(result.single.meta?['musicBrainzReleaseDate'], '2009-01-05');
    });

    test('preserves existing meta keys and flags no-op results unchanged', () {
      final songs = [
        _song('a', '叶惠美', meta: {'pubtime': 100, 'custom': 'x'}),
      ];
      final result = applyMusicBrainzReleaseDates(songs, const [
        MusicBrainzRelease(title: '叶惠美', firstReleaseDate: '2003'),
      ]);

      expect(result.single.meta?['pubtime'], 100);
      expect(result.single.meta?['custom'], 'x');
      expect(result.single.meta?['musicBrainzReleaseDate'], '2003');

      // 没有匹配时直接返回原列表实例，避免无意义的 rebuild。
      final untouched = applyMusicBrainzReleaseDates(songs, const [
        MusicBrainzRelease(title: '别的专辑', firstReleaseDate: '2001'),
      ]);
      expect(identical(untouched, songs), isTrue);
    });
  });

  group('MBRequestGate', () {
    test(
      'serializes concurrent tasks and waits the minimum interval',
      () async {
        final waits = <Duration>[];
        final fixed = DateTime(2026);
        final gate = MBRequestGate(
          clock: () => fixed,
          sleep: (duration) async => waits.add(duration),
        );
        var running = 0;
        var maxRunning = 0;

        Future<int> task(int value) async {
          running++;
          if (running > maxRunning) maxRunning = running;
          await Future<void>.delayed(Duration.zero);
          running--;
          return value;
        }

        final results = await Future.wait([
          gate.run(() => task(1)),
          gate.run(() => task(2)),
          gate.run(() => task(3)),
        ]);

        expect(results, [1, 2, 3]);
        expect(maxRunning, 1, reason: '同一个 gate 内不允许并发请求');
        expect(waits.length, 2, reason: '首个请求无需等待，后续每个都要补齐间隔');
        expect(
          waits.every((d) => d == const Duration(milliseconds: 1100)),
          isTrue,
        );
      },
    );

    test('a failing task still releases the queue', () async {
      final gate = MBRequestGate(
        clock: () => DateTime(2026),
        sleep: (_) async {},
      );

      await expectLater(
        gate.run<int>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(await gate.run<int>(() async => 7), 7);
    });
  });

  group('MusicBrainzDiscography', () {
    test(
      'looks up the artist once, then pages releases with the gate',
      () async {
        final seen = <RequestOptions>[];
        final dio = _fakeDio((options, index) {
          if (options.uri.path.endsWith('/artist/')) {
            return _artistSearch('周杰伦');
          }
          return _releaseGroups([
            {'title': '叶惠美', 'first-release-date': '2003-07-31'},
            {'title': '七里香', 'first-release-date': '2004-08-03'},
          ]);
        }, seen: seen);
        final gate = MBRequestGate(
          clock: () => DateTime(2026),
          sleep: (_) async {},
        );
        final discography = MusicBrainzDiscography(dio, gate: gate);

        final releases = await discography.releasesFor('周杰伦');
        expect(releases.map((r) => r.title), ['叶惠美', '七里香']);
        expect(seen, hasLength(2));
        expect(seen.first.uri.path, endsWith('/artist/'));
        expect(seen.last.uri.queryParameters['artist'], 'mbid-1');
        expect(seen.last.uri.queryParameters['offset'], '0');
      },
    );

    test('reuses the cached future for repeat lookups', () async {
      final seen = <RequestOptions>[];
      final dio = _fakeDio(
        (options, index) => options.uri.path.endsWith('/artist/')
            ? _artistSearch('歌手')
            : _releaseGroups([
                {'title': '专辑', 'first-release-date': '2020-01-01'},
              ]),
        seen: seen,
      );
      final discography = MusicBrainzDiscography(
        dio,
        gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
      );

      final first = await discography.releasesFor('歌手');
      final second = await discography.releasesFor(' 歌手 ');
      expect(identical(first, second), isTrue);
      expect(seen, hasLength(2), reason: '第二次查询必须走缓存，不再发请求');
    });

    test('degrades to an empty list when the transport fails', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, interceptor) => interceptor.reject(
            DioException.connectionError(
              requestOptions: options,
              reason: 'offline',
            ),
          ),
        ),
      );
      final discography = MusicBrainzDiscography(
        dio,
        gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
      );

      expect(await discography.releasesFor('歌手'), isEmpty);
    });

    test(
      'accepts a high-confidence near match but rejects a weak one',
      () async {
        Map<String, dynamic> releases(RequestOptions options) =>
            _releaseGroups([
              {'title': '专辑', 'first-release-date': '2018'},
            ]);

        final strong = MusicBrainzDiscography(
          _fakeDio(
            (options, index) => options.uri.path.endsWith('/artist/')
                ? _artistSearch('Jay Chou', score: 95, id: 'mbid-jay')
                : releases(options),
          ),
          gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
        );
        expect(await strong.releasesFor('周杰伦'), hasLength(1));

        final seen = <RequestOptions>[];
        final weak = MusicBrainzDiscography(
          _fakeDio(
            (options, index) => options.uri.path.endsWith('/artist/')
                ? _artistSearch('Jay Chou', score: 60)
                : _releaseGroups([
                    {'title': '专辑', 'first-release-date': '2018'},
                  ]),
            seen: seen,
          ),
          gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
        );
        expect(await weak.releasesFor('周杰伦'), isEmpty);
        expect(seen, hasLength(1), reason: '低置信度直接放弃，不浏览发行目录');
      },
    );

    test('stops paging when a short page arrives', () async {
      final seen = <RequestOptions>[];
      final dio = _fakeDio(
        (options, index) => options.uri.path.endsWith('/artist/')
            ? _artistSearch('歌手')
            : _releaseGroups([
                {'title': '专辑$index', 'first-release-date': '2020'},
              ]),
        seen: seen,
      );
      final discography = MusicBrainzDiscography(
        dio,
        pageSize: 50,
        gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
      );

      final releases = await discography.releasesFor('歌手');
      expect(releases, hasLength(1));
      expect(seen, hasLength(2));
    });

    test('stops at maxPages for artists with huge discographies', () async {
      final seen = <RequestOptions>[];
      final dio = _fakeDio(
        (options, index) => options.uri.path.endsWith('/artist/')
            ? _artistSearch('歌手')
            : _releaseGroups([
                {'title': '专辑$index', 'first-release-date': '2020'},
              ]),
        seen: seen,
      );
      final discography = MusicBrainzDiscography(
        dio,
        pageSize: 1,
        maxPages: 2,
        gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
      );

      final releases = await discography.releasesFor('歌手');
      expect(releases, hasLength(2));
      expect(seen, hasLength(3), reason: '1 次歌手查询 + 最多 2 页');
    });

    test(
      'escapes quotes so a malformed query cannot break the syntax',
      () async {
        final seen = <RequestOptions>[];
        final dio = _fakeDio(
          (options, index) => options.uri.path.endsWith('/artist/')
              ? _artistSearch('AC"DC')
              : _releaseGroups(const []),
          seen: seen,
        );
        final discography = MusicBrainzDiscography(
          dio,
          gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
        );

        await discography.releasesFor('AC"DC');
        expect(seen.first.uri.queryParameters['query'], 'artist:"AC DC"');
      },
    );
  });

  group('MusicBrainzDiscography.tracksForRelease', () {
    Map<String, dynamic> releaseSearch(String title, {int score = 100}) => {
      'releases': [
        {'id': 'rel-1', 'title': title, 'score': score},
      ],
    };

    Map<String, dynamic> releaseDetail(List<Map<String, dynamic>> discs) => {
      'media': discs,
    };

    test('reads every disc and offsets positions across discs', () async {
      final dio = _fakeDio((options, index) {
        if (options.uri.path.endsWith('/release/')) {
          return releaseSearch('叶惠美');
        }
        expect(options.uri.queryParameters['inc'], 'recordings');
        return releaseDetail([
          {
            'tracks': [
              {'position': 1, 'title': '以父之名', 'length': 342000},
              {'position': 2, 'title': '懦夫', 'length': 218000},
            ],
          },
          {
            'tracks': [
              {'position': 1, 'title': '东风破', 'length': 315000},
            ],
          },
        ]);
      });
      final discography = MusicBrainzDiscography(
        dio,
        gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
      );

      final tracks = await discography.tracksForRelease('周杰伦', '叶惠美');
      expect(tracks.map((t) => t.position), [1, 2, 3]);
      expect(tracks.map((t) => t.title), ['以父之名', '懦夫', '东风破']);
      expect(tracks.first.length, const Duration(milliseconds: 342000));
    });

    test('rejects a release whose title does not match', () async {
      final seen = <RequestOptions>[];
      final dio = _fakeDio(
        (options, index) => releaseSearch('别的专辑'),
        seen: seen,
      );
      final discography = MusicBrainzDiscography(
        dio,
        gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
      );

      expect(await discography.tracksForRelease('周杰伦', '叶惠美'), isEmpty);
      expect(seen, hasLength(1), reason: '标题不匹配时不再读 release 详情');
    });

    test('returns empty when the album title is blank', () async {
      final seen = <RequestOptions>[];
      final discography = MusicBrainzDiscography(
        _fakeDio((options, index) => releaseSearch('x'), seen: seen),
        gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
      );

      expect(await discography.tracksForRelease('周杰伦', '  '), isEmpty);
      expect(seen, isEmpty);
    });

    test('caches the track list per artist and album', () async {
      final seen = <RequestOptions>[];
      final dio = _fakeDio((options, index) {
        if (options.uri.path.endsWith('/release/')) {
          return releaseSearch('叶惠美');
        }
        return releaseDetail([
          {
            'tracks': [
              {'position': 1, 'title': '以父之名', 'length': 342000},
            ],
          },
        ]);
      }, seen: seen);
      final discography = MusicBrainzDiscography(
        dio,
        gate: MBRequestGate(clock: () => DateTime(2026), sleep: (_) async {}),
      );

      final first = await discography.tracksForRelease('周杰伦', '叶惠美');
      final second = await discography.tracksForRelease(' 周杰伦 ', '叶惠美 ');
      expect(identical(first, second), isTrue);
      expect(seen, hasLength(2), reason: '第二次直接命中缓存');
    });
  });
}
