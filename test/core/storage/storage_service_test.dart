import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('false SharedPreferences result is a storage failure', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService.forTesting(
      prefs,
      writeOverride: (operation, key, value) async => false,
    );

    await expectLater(
      storage.setBool('wifi_only_download', false),
      throwsA(
        isA<StorageWriteException>().having(
          (error) => error.key,
          'key',
          'wifi_only_download',
        ),
      ),
    );
  });

  test('snapshot restore preserves absent and typed values', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 2});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService.forTesting(prefs);
    final before = storage.snapshot({'theme_mode', 'search_history'});

    await storage.setInt('theme_mode', 1);
    await storage.setStringList('search_history', ['new']);
    await storage.restore(before);

    expect(storage.getInt('theme_mode'), 2);
    expect(prefs.containsKey('search_history'), isFalse);
  });

  test('getJson heals corrupted values instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'broken_syntax': '{not json',
      'wrong_shape': '[1,2,3]',
      'broken_element': '["ok", 42}',
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService.forTesting(prefs);

    expect(storage.getJson('broken_syntax'), isNull);
    expect(storage.getJson('wrong_shape'), isNull);

    // 损坏的列表数据触发隔离删除。
    expect(storage.getJsonList('broken_element'), isEmpty);

    await pumpEventQueue();
    expect(prefs.containsKey('broken_syntax'), isFalse);
    expect(prefs.containsKey('wrong_shape'), isFalse);
    expect(prefs.containsKey('broken_element'), isFalse);
  });

  test('getJsonList heals corrupted values instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'broken_list': '["ok", 42}',
      'not_a_list': '{"a":1}',
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService.forTesting(prefs);

    expect(storage.getJsonList('broken_list'), isEmpty);
    expect(storage.getJsonList('not_a_list'), isEmpty);
  });

  test(
    'restorePreserving attempts every key and rethrows original error',
    () async {
      SharedPreferences.setMockInitialValues({'first': 1, 'second': 2});
      final prefs = await SharedPreferences.getInstance();
      var restoring = false;
      final attempted = <String>[];
      final storage = StorageService.forTesting(
        prefs,
        writeOverride: (operation, key, value) async {
          if (restoring) {
            attempted.add(key);
            if (key == 'first') return false;
          }
          return switch (value) {
            int intValue => prefs.setInt(key, intValue),
            _ => prefs.remove(key),
          };
        },
      );
      final before = storage.snapshot({'first', 'second'});
      await storage.setInt('first', 10);
      await storage.setInt('second', 20);
      final original = StateError('original write failed');
      late final StackTrace originalStack;
      try {
        throw original;
      } catch (_, stackTrace) {
        originalStack = stackTrace;
      }
      restoring = true;
      final rollbackErrors = <Object>[];

      Object? caught;
      StackTrace? caughtStack;
      try {
        await storage.restorePreserving(
          before,
          original,
          originalStack,
          onRollbackError: (error, _) => rollbackErrors.add(error),
        );
      } catch (error, stackTrace) {
        caught = error;
        caughtStack = stackTrace;
      }

      expect(caught, same(original));
      expect(caughtStack.toString(), originalStack.toString());
      expect(attempted, ['first', 'second']);
      expect(rollbackErrors, [isA<StorageWriteException>()]);
      expect(storage.getInt('first'), 10);
      expect(storage.getInt('second'), 2);
    },
  );
}
