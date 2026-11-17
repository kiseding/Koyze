import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 下载目录的持久化：默认是「没有值」而不是某条绝对路径。
///
/// 存绝对路径会把默认位置钉死在当时那台机器上——装到别的盘、换台机器、
/// 或者便携模式换了 exe 位置，路径就失效了。所以「恢复默认」是删键。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> storageWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return StorageService.forTesting(await SharedPreferences.getInstance());
  }

  test('an empty store means the platform default', () async {
    final storage = await storageWith(<String, Object>{});
    final notifier = DownloadDirectoryNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value, isNull);
  });

  test('a stored folder is loaded as the custom value', () async {
    final storage = await storageWith({'download_directory': '/music/koyze'});
    final notifier = DownloadDirectoryNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value, '/music/koyze');
  });

  test('blank values fall back to the default instead of an empty path',
      () async {
    final storage = await storageWith({'download_directory': '   '});
    final notifier = DownloadDirectoryNotifier(storage: () async => storage);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value, isNull);
  });

  test('picking a folder persists it; restoring default removes the key',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final notifier = DownloadDirectoryNotifier(
      storage: () async => StorageService.forTesting(prefs),
    );

    await notifier.setDirectory('  /music/koyze  ');
    expect(notifier.value, '/music/koyze');
    expect(prefs.getString('download_directory'), '/music/koyze');

    await notifier.setDirectory(null);
    expect(notifier.value, isNull);
    expect(
      prefs.getString('download_directory'),
      isNull,
      reason: '恢复默认是删键，不是写一条平台默认的绝对路径',
    );
  });
}
