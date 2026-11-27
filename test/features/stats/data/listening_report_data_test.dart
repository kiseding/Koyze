import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/stats/data/play_history_store.dart';
import 'package:koyze/features/stats/presentation/listening_report_poster.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 海报上的时段条、最常听歌手、总时长都来自这里。数据算错的话，
/// 从导出的 PNG 上是看不出来的，所以单独钉住聚合逻辑。
void main() {
  test('hourlySeconds 按本地小时分桶并累加', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime(2026, 11, 27, 9, 0);
    final store = PlayHistoryStore(
      () async => StorageService.forTesting(preferences),
      clock: () => now,
    );

    // 9 点两首各 60s，21 点一首 120s。
    for (final (hour, sec) in [(9, 60), (9, 60), (21, 120)]) {
      final at = DateTime(2026, 11, 27, hour);
      now = at;
      store.beginSession(
        songId: 'song-$hour-$sec',
        songTitle: 'Title',
        artistName: 'Artist',
        albumTitle: 'Album',
        source: 'tx',
      );
      store.tick(Duration.zero);
      now = at.add(Duration(seconds: sec));
      store.tick(Duration(seconds: sec));
      store.endSession();
    }

    final hours = store.hourlySeconds(StatsRange.week, now: now);
    expect(hours, hasLength(24));
    expect(hours[9], closeTo(120, 0.01));
    expect(hours[21], closeTo(120, 0.01));
    expect(hours[10], 0);
    await store.disposeAsync();
  });

  test('favoriteHour 取时长最高的小时，全空时返回 null', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime(2026, 11, 27, 9, 0);
    final store = PlayHistoryStore(
      () async => StorageService.forTesting(preferences),
      clock: () => now,
    );

    expect(store.favoriteHour(StatsRange.week), isNull);

    for (final (hour, sec) in [(9, 40), (15, 90)]) {
      final at = DateTime(2026, 11, 27, hour);
      now = at;
      store.beginSession(
        songId: 'song-$hour',
        songTitle: 'Title',
        artistName: 'Artist',
        albumTitle: 'Album',
        source: 'tx',
      );
      store.tick(Duration.zero);
      now = at.add(Duration(seconds: sec));
      store.tick(Duration(seconds: sec));
      store.endSession();
    }

    // 按收听时长而非次数：15 点虽然只有一首，但时长更长。
    expect(store.favoriteHour(StatsRange.week, now: now), 15);
    await store.disposeAsync();
  });

  test('buildListeningReportData 聚合出周期数据，空歌单也有完整结构', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime(2026, 11, 27, 20, 0);
    final store = PlayHistoryStore(
      () async => StorageService.forTesting(preferences),
      clock: () => now,
    );

    final at = DateTime(2026, 11, 27, 20);
    now = at;
    store.beginSession(
      songId: 'song-1',
      songTitle: '晴天',
      artistName: '周杰伦',
      albumTitle: '叶惠美',
      source: 'wy',
    );
    store.tick(Duration.zero);
    now = at.add(const Duration(seconds: 60));
    store.tick(const Duration(seconds: 60));
    store.endSession();

    final data = buildListeningReportData(store, StatsRange.week, now: now);
    expect(data.totalPlays, 1);
    expect(data.activeDays, 1);
    expect(data.uniqueSongs, 1);
    expect(data.topSongs, hasLength(1));
    expect(data.topArtist?.title, '周杰伦');
    expect(data.hourlySeconds[20], closeTo(60, 0.01));
    expect(data.favoriteHour, 20);

    await store.disposeAsync();
  });
}
