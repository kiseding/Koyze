import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/ai/domain/ai_schedule.dart';
import 'package:koyze/features/ai/domain/ai_schedule_store.dart';
import 'package:koyze/features/ai/presentation/ai_schedule_provider.dart';

AiScheduledTask task(String id, {int minute = 480}) => AiScheduledTask(
  id: id,
  title: '任务 $id',
  prompt: '做点事',
  minuteOfDay: minute,
);

void main() {
  late StorageService storage;
  late AiSchedulesNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = StorageService.forTesting(await SharedPreferences.getInstance());
    notifier = AiSchedulesNotifier(storage: () async => storage);
    await pumpEventQueue();
  });

  test('先读盘里的任务，再按顺序合并新加的', () async {
    await notifier.add(task('a'));
    await notifier.add(task('b'));

    expect(notifier.value.map((item) => item.id), ['a', 'b']);
    expect(
      storage.getJsonList(AiScheduleStore.storageKey).map((row) => row['id']),
      ['a', 'b'],
    );
  });

  test('修改只碰目标那条，id 不变', () async {
    await notifier.add(task('a'));
    await notifier.add(task('b'));

    final target = notifier.value.firstWhere((item) => item.id == 'b');
    await notifier.update(
      target.copyWith(title: '改过的名字', minuteOfDay: 21 * 60),
    );

    expect(notifier.value.length, 2);
    expect(notifier.value.first.title, '任务 a');
    final updated = notifier.value.last;
    expect(updated.id, 'b');
    expect(updated.title, '改过的名字');
    expect(updated.timeLabel, '21:00');
  });

  test('暂停开关落盘', () async {
    await notifier.add(task('a'));
    await notifier.setEnabled('a', false);

    expect(notifier.value.single.enabled, isFalse);
    expect(
      storage.getJsonList(AiScheduleStore.storageKey).single['enabled'],
      isFalse,
    );
  });

  test('记成功会清掉上一次的失败原因', () async {
    await notifier.add(task('a'));
    await notifier.recordRun(
      'a',
      at: DateTime(2026, 10, 28, 8),
      failure: 'rateLimited',
      ok: false,
    );
    expect(notifier.value.single.lastOk, isFalse);
    expect(notifier.value.single.lastFailure, 'rateLimited');

    await notifier.recordRun(
      'a',
      at: DateTime(2026, 10, 29, 8),
      result: '挑了 8 首',
      ok: true,
    );
    final after = notifier.value.single;
    expect(after.lastOk, isTrue);
    expect(after.lastResult, '挑了 8 首');
    expect(after.lastFailure, isNull);
    expect(after.lastRunAt, DateTime(2026, 10, 29, 8));
  });

  test('删除后列表和磁盘都不再有它', () async {
    await notifier.add(task('a'));
    await notifier.add(task('b'));
    await notifier.remove('a');

    expect(notifier.value.single.id, 'b');
    expect(
      storage.getJsonList(AiScheduleStore.storageKey).map((row) => row['id']),
      ['b'],
    );
  });

  test('全部删完后清掉存储键，不留下空数组', () async {
    await notifier.add(task('a'));
    await notifier.remove('a');

    expect(notifier.value, isEmpty);
    expect(storage.getString(AiScheduleStore.storageKey), isNull);
  });
}
