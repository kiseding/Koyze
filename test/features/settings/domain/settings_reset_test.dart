import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/settings/domain/settings_reset.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<StorageService> _storage() async {
  SharedPreferences.setMockInitialValues({});
  return StorageService.forTesting(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('removes every resettable preference', () async {
    final storage = await _storage();
    for (final key in kResettablePreferenceKeys) {
      await storage.setString(key, 'value');
    }

    final removed = await resetPreferences(storage);

    expect(removed, kResettablePreferenceKeys.length);
    for (final key in kResettablePreferenceKeys) {
      expect(storage.getString(key), isNull, reason: '$key should be gone');
    }
  });

  test('keeps account data, library index and language', () async {
    final storage = await _storage();
    for (final key in kPreservedPreferenceKeys) {
      await storage.setString(key, 'keep-me');
    }
    await storage.setString('theme_mode', 'dark');

    await resetPreferences(storage);

    for (final key in kPreservedPreferenceKeys) {
      expect(storage.getString(key), 'keep-me', reason: '$key must survive');
    }
    expect(storage.getString('theme_mode'), isNull);
  });

  test('counts only keys that actually existed', () async {
    final storage = await _storage();
    await storage.setString('theme_mode', 'light');
    await storage.setString('audio_quality', 'flac');

    expect(await resetPreferences(storage), 2);
    expect(await resetPreferences(storage), 0);
  });

  test('keeps the new playback toggles in the resettable set', () {
    const expected = [
      'lock_screen_lyric_enabled',
      'precache_recent_enabled',
      'precache_recent_count',
      'replay_gain_enabled',
      'playback_speed',
    ];
    for (final key in expected) {
      expect(kResettablePreferenceKeys, contains(key));
    }
  });

  test('never lists the same key twice', () {
    expect(
      kResettablePreferenceKeys.toSet(),
      hasLength(kResettablePreferenceKeys.length),
    );
    expect(
      kPreservedPreferenceKeys.toSet(),
      hasLength(kPreservedPreferenceKeys.length),
    );
  });

  test('no key is both resettable and preserved', () {
    final preserved = kPreservedPreferenceKeys.toSet();
    for (final key in kResettablePreferenceKeys) {
      expect(preserved, isNot(contains(key)));
    }
  });
}
