import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/ai_schedule.dart';

AiScheduledTask daily({
  int minuteOfDay = 8 * 60,
  bool enabled = true,
  DateTime? lastRunAt,
}) => AiScheduledTask(
  id: 't1',
  title: '早安推荐',
  prompt: '挑 8 首适合早上听的歌',
  minuteOfDay: minuteOfDay,
  enabled: enabled,
  lastRunAt: lastRunAt,
);

void main() {
  group('dueAt', () {
    test('到点后补跑今天这一次，还没到点不跑', () {
      final task = daily();
      expect(task.dueAt(DateTime(2026, 10, 28, 7, 59)), isNull);
      expect(task.dueAt(DateTime(2026, 10, 28, 8, 0)), DateTime(2026, 10, 28, 8));
      expect(
        task.dueAt(DateTime(2026, 10, 28, 11, 30)),
        DateTime(2026, 10, 28, 8),
      );
    });

    test('超过 6 小时就不再补跑，避免开应用时突然翻出很早的任务', () {
      final task = daily();
      expect(task.dueAt(DateTime(2026, 10, 28, 14, 5)), isNull);
      // 6 小时整还在窗口里。
      expect(
        task.dueAt(DateTime(2026, 10, 28, 14, 0)),
        DateTime(2026, 10, 28, 8),
      );
    });

    test('已经跑过的计划时刻不会重复触发', () {
      final run = daily(lastRunAt: DateTime(2026, 10, 28, 8));
      expect(run.dueAt(DateTime(2026, 10, 28, 9)), isNull);
      // 第二天到点又是新的一次。
      expect(
        run.dueAt(DateTime(2026, 10, 29, 8, 1)),
        DateTime(2026, 10, 29, 8),
      );
    });

    test('凌晨打开应用时，昨天错过的还能补上', () {
      final run = daily(lastRunAt: DateTime(2026, 10, 27, 8));
      // 28 号 01:00：今天的还没到，昨天 08:00 距今 17 小时——超出窗口。
      expect(run.dueAt(DateTime(2026, 10, 28, 1)), isNull);
      // 28 号 02:00 配 20:00 的任务：昨晚 20:00 距今 6 小时，正好补上。
      final evening = daily(minuteOfDay: 20 * 60, lastRunAt: DateTime(2026, 10, 26, 20));
      expect(
        evening.dueAt(DateTime(2026, 10, 28, 2)),
        DateTime(2026, 10, 27, 20),
      );
    });

    test('暂停的任务永远不跑', () {
      final task = daily(enabled: false);
      expect(task.dueAt(DateTime(2026, 10, 28, 9)), isNull);
    });

    test('工作日任务只在周一到周五触发', () {
      const task = AiScheduledTask(
        id: 't2',
        title: '工作日',
        prompt: '整理歌单',
        minuteOfDay: 9 * 60,
        cadence: AiScheduleCadence.weekdays,
      );
      // 2026-10-31 是周六。
      expect(task.dueAt(DateTime(2026, 10, 31, 10)), isNull);
      // 2026-11-02 是周一。
      expect(
        task.dueAt(DateTime(2026, 11, 2, 10)),
        DateTime(2026, 11, 2, 9),
      );
    });

    test('每周任务在指定的星期几触发', () {
      const task = AiScheduledTask(
        id: 't3',
        title: '周末回顾',
        prompt: '整理上周常听',
        minuteOfDay: 21 * 60,
        cadence: AiScheduleCadence.weekly,
        weekday: DateTime.sunday,
      );
      expect(task.runsOn(DateTime(2026, 11, 1)), isTrue); // 周日
      expect(task.runsOn(DateTime(2026, 11, 2)), isFalse); // 周一
      expect(
        task.dueAt(DateTime(2026, 11, 1, 21, 5)),
        DateTime(2026, 11, 1, 21),
      );
    });
  });

  group('nextRunAfter', () {
    test('今天还没到点就是今天', () {
      final task = daily();
      expect(
        task.nextRunAfter(DateTime(2026, 10, 28, 7)),
        DateTime(2026, 10, 28, 8),
      );
    });

    test('今天已经过了就顺延到下一次', () {
      final task = daily();
      expect(
        task.nextRunAfter(DateTime(2026, 10, 28, 9)),
        DateTime(2026, 10, 29, 8),
      );
    });

    test('每周任务跨过本周后跳到下周同一天', () {
      const task = AiScheduledTask(
        id: 't4',
        title: '周一计划',
        prompt: '排这周的歌单',
        minuteOfDay: 7 * 60,
        cadence: AiScheduleCadence.weekly,
        weekday: DateTime.monday,
      );
      // 2026-10-28 是周三。
      expect(
        task.nextRunAfter(DateTime(2026, 10, 28, 12)),
        DateTime(2026, 11, 2, 7),
      );
    });
  });

  test('时间标签补零', () {
    expect(daily(minuteOfDay: 0).timeLabel, '00:00');
    expect(daily(minuteOfDay: 8 * 60 + 5).timeLabel, '08:05');
    expect(daily(minuteOfDay: 23 * 60 + 59).timeLabel, '23:59');
  });

  test('JSON 往返保留状态，越界的时间会被夹回合法范围', () {
    final task = AiScheduledTask(
      id: 't5',
      title: '夜间',
      prompt: '推一首助眠',
      minuteOfDay: 22 * 60 + 30,
      cadence: AiScheduleCadence.weekly,
      weekday: DateTime.friday,
      enabled: false,
      lastRunAt: DateTime(2026, 10, 23, 22, 30),
      lastResult: '推了《雨》',
      lastOk: true,
    );
    final restored = AiScheduledTask.fromJson(task.toJson())!;
    expect(restored.title, '夜间');
    expect(restored.minuteOfDay, 22 * 60 + 30);
    expect(restored.cadence, AiScheduleCadence.weekly);
    expect(restored.weekday, DateTime.friday);
    expect(restored.enabled, isFalse);
    expect(restored.lastRunAt, DateTime(2026, 10, 23, 22, 30));
    expect(restored.lastResult, '推了《雨》');
    expect(restored.lastOk, isTrue);

    final broken = AiScheduledTask.fromJson({
      'id': 't6',
      'title': 'x',
      'prompt': 'y',
      'minuteOfDay': 5000,
      'weekday': 99,
      'cadence': 'monthly',
    })!;
    expect(broken.minuteOfDay, 1439);
    expect(broken.weekday, DateTime.sunday);
    expect(broken.cadence, AiScheduleCadence.daily);
  });

  test('缺字段或空标题的记录会被丢掉', () {
    expect(AiScheduledTask.fromJson(null), isNull);
    expect(AiScheduledTask.fromJson({'id': 'a', 'title': '', 'prompt': 'p'}), isNull);
    expect(AiScheduledTask.fromJson({'id': 'a', 'title': 't'}), isNull);
    expect(AiScheduledTask.fromJson('not a map'), isNull);
  });

  test('失败原因也进 JSON，成功时会被清空', () {
    final failed = const AiScheduledTask(
      id: 't7',
      title: 'x',
      prompt: 'y',
      minuteOfDay: 60,
    ).copyWith(lastFailure: 'rateLimited', lastOk: false, lastResult: '');
    expect(failed.toJson()['lastFailure'], 'rateLimited');

    final ok = failed.copyWith(lastFailure: '', lastOk: true, lastResult: '好了');
    expect(ok.toJson().containsKey('lastFailure'), isFalse);
  });
}
