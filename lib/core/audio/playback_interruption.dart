/// Interruption bookkeeping for the audio handler.
///
/// Extracted from `lib/core/audio/audio_handler.dart` (which had grown past
/// 4000 lines). These types were already pure — they hold no streams, no
/// platform channels and no references to the handler — so moving them costs
/// nothing and lets the policy be read and tested without the audio stack.
library;

/// What the handler should do in response to an interruption transition.
enum InterruptionAction {
  none,
  pausePreservingIntent,
  pauseClearingIntent,
  resume,
  duck,
  unduck,
}

/// Tracks nested audio interruptions (phone call, another app ducking us, a
/// headphone unplug) and decides what to do on each transition.
///
/// Interruptions nest: a call can begin while a navigation prompt is already
/// ducking us. Only the outermost begin/end pair is allowed to change playback
/// state, which is why every transition returns `none` while `depth > 0`.
///
/// The three pieces of state that must survive until the outermost end:
///
/// * [ownsPause] — whether *we* paused the player. We must not resume music the
///   user had already paused themselves.
/// * [ducking] — whether the interruption was a duck rather than a pause, which
///   decides between `unduck` and `resume`.
/// * [mayResume] — latched false by any nested `onEnd(mayResume: false)`, so an
///   inner client vetoing resume is not overridden by an outer one.
class AudioInterruptionPolicy {
  int _depth = 0;
  bool _ownsPause = false;
  bool _ducking = false;
  bool _mayResume = true;

  bool get active => _depth > 0;
  int get depth => _depth;

  InterruptionAction onBegin({required bool wasPlaying, bool duck = false}) {
    _depth++;
    if (_depth > 1) return InterruptionAction.none;
    _ownsPause = wasPlaying && !duck;
    _ducking = duck;
    _mayResume = true;
    if (duck) return InterruptionAction.duck;
    return wasPlaying
        ? InterruptionAction.pausePreservingIntent
        : InterruptionAction.none;
  }

  InterruptionAction onEnd({
    required bool userStillWantsPlay,
    required bool mayResume,
  }) {
    if (_depth == 0) return InterruptionAction.none;
    if (!mayResume) _mayResume = false;
    _depth--;
    if (_depth > 0) return InterruptionAction.none;
    final ownsPause = _ownsPause;
    final ducking = _ducking;
    final cycleMayResume = _mayResume;
    _ownsPause = false;
    _ducking = false;
    _mayResume = true;
    if (ducking && cycleMayResume) return InterruptionAction.unduck;
    return ownsPause && userStillWantsPlay && cycleMayResume
        ? InterruptionAction.resume
        : InterruptionAction.none;
  }

  /// Headphones unplugged: always pause, and forget any nesting so a later
  /// `onEnd` from a still-open interruption cannot resume.
  InterruptionAction onBecomingNoisy() {
    _depth = 0;
    _ownsPause = false;
    _ducking = false;
    _mayResume = true;
    return InterruptionAction.pausePreservingIntent;
  }
}

/// Snapshot of the generations that gate a playback start.
///
/// A start request can complete after an interruption or a blocking transition
/// has happened; comparing this snapshot against the live counters tells the
/// caller whether its result is still allowed to touch the player.
class PlaybackStartProvenance {
  final int interruptionGeneration;
  final int blockGeneration;

  const PlaybackStartProvenance(
    this.interruptionGeneration,
    this.blockGeneration,
  );
}
