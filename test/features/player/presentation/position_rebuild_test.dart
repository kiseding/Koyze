import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';

/// 播放器进度是全局最高频的状态源（每秒多次），
/// `PositionNotifier` 必须只在**位置真的变化**时才通知监听者。
/// 如果它对每个 tick 都发通知，整棵播放器子树会以 60fps 重建。
void main() {
  test('相同的播放位置不会重复通知', () {
    final notifier = PositionNotifier(null);
    addTearDown(notifier.dispose);
    var notifications = 0;
    notifier.addListener((_) => notifications++, fireImmediately: false);

    notifier.update(Duration.zero);
    notifier.update(const Duration(seconds: 1));
    notifier.update(const Duration(seconds: 1));

    expect(notifier.value, const Duration(seconds: 1));
    expect(notifications, 1);
  });

  test('位置每次变化都会通知', () {
    final notifier = PositionNotifier(null);
    addTearDown(notifier.dispose);
    final seen = <Duration>[];
    notifier.addListener((value) => seen.add(value), fireImmediately: false);

    notifier.update(const Duration(milliseconds: 100));
    notifier.update(const Duration(milliseconds: 200));
    notifier.update(const Duration(milliseconds: 300));

    expect(seen, const [
      Duration(milliseconds: 100),
      Duration(milliseconds: 200),
      Duration(milliseconds: 300),
    ]);
  });

  test('位置回退（seek 到前面）也会通知', () {
    final notifier = PositionNotifier(null);
    addTearDown(notifier.dispose);
    final seen = <Duration>[];
    notifier.addListener((value) => seen.add(value), fireImmediately: false);

    notifier.update(const Duration(seconds: 30));
    notifier.update(const Duration(seconds: 5));

    expect(notifier.value, const Duration(seconds: 5));
    expect(seen, const [Duration(seconds: 30), Duration(seconds: 5)]);
  });

  test('dispose 之后不再通知，也不抛异常', () {
    final notifier = PositionNotifier(null);
    var notifications = 0;
    notifier.addListener((_) => notifications++, fireImmediately: false);
    notifier.update(const Duration(seconds: 1));
    expect(notifications, 1);

    notifier.dispose();

    // dispose 后更新不应导致 "used after dispose" 之类的崩溃。
    expect(() => notifier.update(const Duration(seconds: 2)), returnsNormally);
    expect(notifications, 1);
  });

  group('TrackStartGate（切歌立刻归零）', () {
    test('没切歌时全部放行', () {
      final gate = TrackStartGate();
      expect(
        gate.accepts(const Duration(minutes: 3), sourceInstalled: true),
        isTrue,
      );
    });

    test('装源前的归零和旧位置均不能打开闸门', () {
      final gate = TrackStartGate()..arm();
      expect(gate.accepts(Duration.zero, sourceInstalled: false), isFalse);
      expect(
        gate.accepts(const Duration(minutes: 2), sourceInstalled: false),
        isFalse,
      );
      expect(gate.awaiting, isTrue);
    });

    test('新源装好后仍要等到引擎位置回到新曲开头', () {
      final gate = TrackStartGate()..arm();
      expect(
        gate.accepts(const Duration(minutes: 2), sourceInstalled: true),
        isFalse,
      );
      expect(gate.accepts(Duration.zero, sourceInstalled: true), isTrue);
      expect(gate.awaiting, isFalse);
      expect(
        gate.accepts(const Duration(minutes: 2), sourceInstalled: true),
        isTrue,
      );
    });
  });
}
