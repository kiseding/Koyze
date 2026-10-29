import 'dart:async';
import 'dart:math' as math;

import 'package:just_audio/just_audio.dart';

/// Loudness multiplier applied while another app is playing audio.
const double duckedPlaybackVolumeFactor = 0.35;

/// Owns the app-level playback volume and the temporary "duck" state.
///
/// Extracted from `LxAudioHandler` (which had grown to ~4000 lines) because
/// volume is a self-contained concern: it holds two numbers, derives the
/// effective volume, and writes it to whichever [AudioPlayer] is currently
/// installed. Nothing else in the handler needs to know about ducking.
///
/// The controller does not own the player. The handler calls [bindPlayer]
/// whenever the native player is (re)built, which keeps the "reapply desired
/// state after a rebuild" behaviour in one place instead of duplicating the
/// push call at every construction site.
class PlaybackVolumeController {
  AudioPlayer? _player;

  double _volume = 1;
  bool _ducked = false;

  /// 当前曲目的响度补偿（ReplayGain），1 表示不调整。
  double _trackGain = 1;

  /// 临时衰减，睡眠定时的渐弱与其它一次性淡出共用。
  double _temporaryGain = 1;

  Timer? _rampTimer;
  int _rampGeneration = 0;

  /// User-set loudness, 0..1. Unaffected by ducking.
  double get volume => _volume;

  /// 当前曲目的增益倍数。
  double get trackGain => _trackGain;

  /// Effective loudness actually written to the player, 0..1.
  double get effectiveVolume {
    final scaled = _volume * _trackGain * _temporaryGain;
    final ducked = _ducked ? scaled * duckedPlaybackVolumeFactor : scaled;
    return ducked.clamp(0.0, 1.0).toDouble();
  }

  bool get isDucked => _ducked;

  /// Points the controller at a (possibly rebuilt) native player and
  /// immediately reapplies the current effective volume to it.
  void bindPlayer(AudioPlayer player) {
    _player = player;
    push();
  }

  /// Sets the user-facing volume. Values outside 0..1 are clamped.
  void apply(double volume) {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    push();
  }

  /// 换曲时更新响度补偿。0.5~2.0 之外的值按边界处理：
  /// 单个 Tag 写错（例如 20 dB）不应该让整首歌静音或炸响。
  void setTrackGain(double gain) {
    final next = gain.isFinite ? gain.clamp(0.5, 2.0).toDouble() : 1.0;
    if (next == _trackGain) return;
    _trackGain = next;
    push();
  }

  /// 当前的一次性衰减倍数。
  double get temporaryGain => _temporaryGain;

  /// 睡眠定时渐弱用的一次性衰减，不改用户音量。
  void setTemporaryGain(double gain) {
    final next = gain.isFinite ? gain.clamp(0.0, 1.0).toDouble() : 1.0;
    if (next == _temporaryGain) return;
    _temporaryGain = next;
    push();
  }

  void clearTemporaryGain() {
    cancelRamp();
    setTemporaryGain(1);
  }

  /// 把一次性衰减平滑地推到 [target]。
  ///
  /// 用余弦缓动而不是线性：两端变化慢、中间快，听感上更像模拟设备的淡入
  /// 淡出，也不会在起始处出现「突然出声」。被新的一次渐变打断时不会调用
  /// [onDone]，调用方据此判断淡出是否真的走完。
  void rampTemporaryGain(
    double target, {
    required Duration duration,
    int steps = 6,
    void Function()? onDone,
  }) {
    cancelRamp();
    final generation = _rampGeneration;
    final to = target.isFinite ? target.clamp(0.0, 1.0).toDouble() : 1.0;
    final from = _temporaryGain;
    final stepDuration = Duration(microseconds: duration.inMicroseconds ~/ steps);
    if (steps <= 0 ||
        duration <= Duration.zero ||
        stepDuration <= Duration.zero) {
      setTemporaryGain(to);
      onDone?.call();
      return;
    }
    var step = 0;
    _rampTimer = Timer.periodic(stepDuration, (timer) {
      if (generation != _rampGeneration) {
        timer.cancel();
        return;
      }
      step++;
      final progress = step / steps;
      final eased = 0.5 - 0.5 * math.cos(math.pi * progress);
      setTemporaryGain(from + (to - from) * eased);
      if (step >= steps) {
        timer.cancel();
        _rampTimer = null;
        // 浮点累加可能差一点点，最后一步直接落到目标值。
        setTemporaryGain(to);
        onDone?.call();
      }
    });
  }

  /// 取消未完成的渐变，保留当前音量。
  void cancelRamp() {
    _rampGeneration++;
    _rampTimer?.cancel();
    _rampTimer = null;
  }

  /// 等待一次渐变结束。被打断时返回 false。
  Future<bool> _settle() {
    final timer = _rampTimer;
    if (timer == null) return Future.value(true);
    final generation = _rampGeneration;
    final completer = Completer<bool>();
    Timer.periodic(const Duration(milliseconds: 10), (poll) {
      if (generation != _rampGeneration) {
        poll.cancel();
        if (!completer.isCompleted) completer.complete(false);
        return;
      }
      if (_rampTimer == null) {
        poll.cancel();
        if (!completer.isCompleted) completer.complete(true);
      }
    });
    return completer.future;
  }

  /// 淡出到静音并等待完成。被打断（例如用户立刻又按了播放）时返回 false。
  Future<bool> fadeOutToSilence(Duration duration) {
    rampTemporaryGain(0, duration: duration);
    return _settle();
  }

  /// Lowers output while another app plays. Idempotent.
  void duck() {
    if (_ducked) return;
    _ducked = true;
    push();
  }

  /// Restores the user's volume after a duck. Idempotent.
  void restore() {
    if (!_ducked) return;
    _ducked = false;
    push();
  }

  /// Writes [effectiveVolume] to the bound player.
  ///
  /// Failures are swallowed on purpose: `setVolume` throws when the player has
  /// been disposed mid-call, and a failed volume write must never surface as a
  /// playback error to the user. The next [push] will reconcile.
  void push() {
    final player = _player;
    if (player == null) return;
    unawaited(
      player.setVolume(effectiveVolume).then<void>((_) {}, onError: (_, _) {}),
    );
  }

  /// Drops the player reference during dispose.
  void detach() {
    _player = null;
  }
}
