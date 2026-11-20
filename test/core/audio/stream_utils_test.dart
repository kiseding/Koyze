import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/stream_utils.dart';

void main() {
  group('mergeStreams', () {
    test('forwards every source and closes only after all close', () async {
      final a = StreamController<int>();
      final b = StreamController<int>();
      final merged = mergeStreams<int>(<Stream<int>>[a.stream, b.stream]);
      final seen = <int>[];
      final done = Completer<void>();
      merged.listen(seen.add, onDone: done.complete);

      a.add(1);
      b.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(seen, <int>[1, 2]);

      // 只关一路时下游必须还活着——播放层靠这条流持续收位置更新。
      await a.close();
      expect(done.isCompleted, isFalse);

      b.add(3);
      await b.close();
      await done.future;
      expect(seen, <int>[1, 2, 3]);
    });

    test('propagates the first error and closes', () async {
      final a = StreamController<int>();
      final merged = mergeStreams<int>(<Stream<int>>[a.stream]);
      Object? caught;
      var closed = false;
      merged.listen(
        (_) {},
        onError: (Object error, StackTrace _) => caught = error,
        onDone: () => closed = true,
      );

      a.addError(StateError('boom'));
      await Future<void>.delayed(Duration.zero);

      expect(caught, isA<StateError>());
      expect(closed, isTrue);
    });

    test('an empty source list yields an already-closed stream', () async {
      final events = await mergeStreams<int>(<Stream<int>>[]).toList();
      expect(events, isEmpty);
    });

    test('cancelling the listener cancels every upstream', () async {
      final a = StreamController<int>(onCancel: () => cancelled.add('a'));
      final b = StreamController<int>(onCancel: () => cancelled.add('b'));
      final subscription = mergeStreams<int>(<Stream<int>>[
        a.stream,
        b.stream,
      ]).listen((_) {});

      await subscription.cancel();
      expect(cancelled, <String>['a', 'b']);
    });
  });

  group('throttleStream', () {
    // 这一组用真实计时器而不是 testWidgets 的 FakeAsync：FakeAsync 下
    // `await source.close()` 这类「等 done 送达」的等待需要外部推微任务队列，
    // 写法稍不注意就整条测试挂死（实测挂满 5 分钟）。窗口取 30ms、检查点
    // 留 3~10 倍余量，比操控假时钟稳。
    const window = Duration(milliseconds: 30);

    test('passes the first value through immediately', () async {
      final source = StreamController<int>();
      final seen = <int>[];
      throttleStream<int>(source.stream, window).listen(seen.add);

      source.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(seen, <int>[1]);

      await source.close();
    });

    test('keeps only the last value inside a window', () async {
      final source = StreamController<int>();
      final seen = <int>[];
      throttleStream<int>(source.stream, window).listen(seen.add);

      source.add(1);
      await Future<void>.delayed(Duration.zero);
      source.add(2);
      source.add(3);
      source.add(4);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // 窗口内一个都不发，否则节流等于没做。
      expect(seen, <int>[1]);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      // 补发的是最后一个值，不是第一个——丢掉尾值会让 UI 停在旧状态。
      expect(seen, <int>[1, 4]);

      await source.close();
    });

    test('flushes the trailing value when the source closes', () async {
      final source = StreamController<int>();
      final seen = <int>[];
      var closed = false;
      throttleStream<int>(
        source.stream,
        window,
      ).listen(seen.add, onDone: () => closed = true);

      source.add(1);
      await Future<void>.delayed(Duration.zero);
      source.add(2);
      await source.close();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(seen, <int>[1, 2]);
      expect(closed, isTrue);
    });

    test('cancelling the listener drops the pending window', () async {
      final source = StreamController<int>();
      final seen = <int>[];
      final subscription = throttleStream<int>(
        source.stream,
        window,
      ).listen(seen.add);

      source.add(1);
      await Future<void>.delayed(Duration.zero);
      source.add(2);
      await subscription.cancel();

      // 取消后窗口定时器必须一起取消：这里等两个窗口再看，不该冒出 2。
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen, <int>[1]);

      await source.close();
    });
  });
}

/// mergeStreams 取消用例收集到的上游取消顺序。
final List<String> cancelled = <String>[];
