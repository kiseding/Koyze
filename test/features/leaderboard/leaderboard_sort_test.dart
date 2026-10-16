import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/leaderboard/presentation/leaderboard_provider.dart';
import 'package:koyze/core/music_source/platform/music_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ensureDefaultLayout builds platform blocks from categories', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final notifier = LeaderboardLayoutNotifier(storage: () async => storage);
    final categories = [
      const LeaderboardCategory(id: 'kw:93', name: '飙升榜', platform: 'kw'),
      const LeaderboardCategory(id: 'tx:4', name: '流行指数榜', platform: 'tx'),
      const LeaderboardCategory(id: 'kw:17', name: '新歌榜', platform: 'kw'),
    ];

    notifier.ensureDefaultLayout(categories);

    expect(notifier.state.map((item) => item.key).toList(), [
      'platform:tx',
      'category:tx:4',
      'platform:kw',
      'category:kw:93',
      'category:kw:17',
    ]);
  });

  test('ensureDefaultLayout does not overwrite existing layout', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final notifier = LeaderboardLayoutNotifier(storage: () async => storage);
    notifier.ensureDefaultLayout(const [
      LeaderboardCategory(id: 'tx:4', name: 'A', platform: 'tx'),
    ]);
    final before = notifier.state.map((item) => item.key).toList();

    notifier.ensureDefaultLayout(const [
      LeaderboardCategory(id: 'kw:93', name: 'A', platform: 'kw'),
    ]);

    expect(notifier.state.map((item) => item.key).toList(), before);
  });

  test('hiding platform hides its categories too', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final notifier = LeaderboardLayoutNotifier(storage: () async => storage);
    notifier.ensureDefaultLayout(const [
      LeaderboardCategory(id: 'kw:93', name: 'A', platform: 'kw'),
      LeaderboardCategory(id: 'kw:17', name: 'B', platform: 'kw'),
      LeaderboardCategory(id: 'tx:4', name: 'C', platform: 'tx'),
    ]);

    notifier.hidePlatform('kw');

    final hiddenKeys = notifier.state
        .where((item) => item.hidden)
        .map((item) => item.key);
    expect(
      hiddenKeys,
      containsAll(['platform:kw', 'category:kw:93', 'category:kw:17']),
    );
    expect(
      notifier.state.where((item) => item.key == 'category:tx:4').single.hidden,
      isFalse,
    );
  });

  test('restoreAll clears hidden flags', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final notifier = LeaderboardLayoutNotifier(storage: () async => storage);
    notifier.ensureDefaultLayout(const [
      LeaderboardCategory(id: 'kw:93', name: 'A', platform: 'kw'),
    ]);
    notifier.hidePlatform('kw');

    notifier.restoreAll();

    expect(notifier.state.every((item) => !item.hidden), isTrue);
  });
}
