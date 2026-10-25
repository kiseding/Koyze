import 'dart:async';

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

  /// User-set loudness, 0..1. Unaffected by ducking.
  double get volume => _volume;

  /// Effective loudness actually written to the player, 0..1.
  double get effectiveVolume =>
      _ducked ? _volume * duckedPlaybackVolumeFactor : _volume;

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
