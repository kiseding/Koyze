import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/playback_volume_controller.dart';

/// Records what the controller would have written to a real player.
///
/// [PlaybackVolumeController] takes an optional `AudioPlayer`, which cannot be
/// constructed headlessly, so the tests drive the pure state machine and assert
/// on [PlaybackVolumeController.effectiveVolume] plus the values it would push.
/// The push itself is a one-line `setVolume` call whose failure is already
/// swallowed by design; asserting on it through a real player would test
/// just_audio, not this class.
void main() {
  group('PlaybackVolumeController volume', () {
    test('defaults to full volume and not ducked', () {
      final controller = PlaybackVolumeController();
      expect(controller.volume, 1.0);
      expect(controller.effectiveVolume, 1.0);
      expect(controller.isDucked, isFalse);
    });

    test('apply clamps out-of-range input', () {
      final controller = PlaybackVolumeController();
      controller.apply(2.5);
      expect(controller.volume, 1.0);
      controller.apply(-1);
      expect(controller.volume, 0.0);
    });

    test('apply stores the exact value inside the range', () {
      final controller = PlaybackVolumeController();
      controller.apply(0.42);
      expect(controller.volume, closeTo(0.42, 1e-9));
    });
  });

  group('PlaybackVolumeController ducking', () {
    test('duck scales the effective volume without changing user volume', () {
      final controller = PlaybackVolumeController()..apply(0.8);

      controller.duck();

      expect(controller.isDucked, isTrue);
      expect(controller.volume, closeTo(0.8, 1e-9), reason: 'user volume');
      expect(
        controller.effectiveVolume,
        closeTo(0.8 * duckedPlaybackVolumeFactor, 1e-9),
      );
    });

    test('restore returns the effective volume to the user value', () {
      final controller = PlaybackVolumeController()..apply(0.5);
      controller.duck();
      controller.restore();

      expect(controller.isDucked, isFalse);
      expect(controller.effectiveVolume, closeTo(0.5, 1e-9));
    });

    test('duck is idempotent', () {
      final controller = PlaybackVolumeController()..apply(1.0);
      controller.duck();
      controller.duck();
      expect(
        controller.effectiveVolume,
        closeTo(duckedPlaybackVolumeFactor, 1e-9),
        reason: 'ducking twice must not compound the multiplier',
      );
    });

    test('restore is idempotent', () {
      final controller = PlaybackVolumeController()..apply(1.0);
      controller.restore();
      expect(controller.effectiveVolume, 1.0);
    });

    test('changing volume while ducked keeps the duck applied', () {
      final controller = PlaybackVolumeController()..apply(1.0);
      controller.duck();
      controller.apply(0.5);

      expect(
        controller.effectiveVolume,
        closeTo(0.5 * duckedPlaybackVolumeFactor, 1e-9),
      );
    });

    test('the duck factor is a real attenuation', () {
      // Guards against a refactor that makes ducking a no-op.
      expect(duckedPlaybackVolumeFactor, lessThan(1.0));
      expect(duckedPlaybackVolumeFactor, greaterThan(0.0));
    });
  });

  group('PlaybackVolumeController gains', () {
    test('track gain scales the effective volume only', () {
      final controller = PlaybackVolumeController()..apply(0.5);

      controller.setTrackGain(1.5);

      expect(controller.volume, closeTo(0.5, 1e-9));
      expect(controller.trackGain, closeTo(1.5, 1e-9));
      expect(controller.effectiveVolume, closeTo(0.75, 1e-9));
    });

    test('track gain is clamped to a sane range', () {
      final controller = PlaybackVolumeController();
      controller.setTrackGain(-3);
      expect(controller.trackGain, 0.5);
      controller.setTrackGain(20);
      expect(controller.trackGain, 2.0);
      controller.setTrackGain(double.nan);
      expect(controller.trackGain, 1.0);
    });

    test('temporary gain fades to silence and back', () {
      final controller = PlaybackVolumeController()..apply(0.8);

      controller.setTemporaryGain(0.25);
      expect(controller.effectiveVolume, closeTo(0.2, 1e-9));

      controller.setTemporaryGain(0);
      expect(controller.effectiveVolume, 0);

      controller.clearTemporaryGain();
      expect(controller.effectiveVolume, closeTo(0.8, 1e-9));
      // 渐弱不应篡改用户设定。
      expect(controller.volume, closeTo(0.8, 1e-9));
    });

    test('gains, ducking and the user volume compose multiplicatively', () {
      final controller = PlaybackVolumeController()..apply(1.0);
      controller.setTrackGain(0.5);
      controller.setTemporaryGain(0.5);
      controller.duck();

      expect(
        controller.effectiveVolume,
        closeTo(0.5 * 0.5 * duckedPlaybackVolumeFactor, 1e-9),
      );
    });

    test(
      'effective volume never exceeds 1 even with a positive track gain',
      () {
        final controller = PlaybackVolumeController()..apply(0.9);
        controller.setTrackGain(2.0);
        expect(controller.effectiveVolume, 1.0);
      },
    );
  });

  group('PlaybackVolumeController fades', () {
    testWidgets('ramps the temporary gain down to silence', (tester) async {
      final controller = PlaybackVolumeController()..apply(1);
      var done = false;

      controller.rampTemporaryGain(
        0,
        duration: const Duration(milliseconds: 120),
        steps: 6,
        onDone: () => done = true,
      );

      expect(controller.temporaryGain, closeTo(1, 1e-9));
      await tester.pump(const Duration(milliseconds: 21));
      final midway = controller.temporaryGain;
      expect(midway, lessThan(1));
      expect(midway, greaterThan(0));

      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.temporaryGain, 0);
      expect(done, isTrue);
    });

    testWidgets('ramps back up for a fade-in', (tester) async {
      final controller = PlaybackVolumeController()..apply(1);
      controller.setTemporaryGain(0);

      controller.rampTemporaryGain(
        1,
        duration: const Duration(milliseconds: 120),
        steps: 6,
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.temporaryGain, closeTo(1, 1e-9));
      // 淡入淡出不能动用户设定的音量。
      expect(controller.volume, closeTo(1, 1e-9));
    });

    testWidgets('a new ramp cancels the previous one', (tester) async {
      final controller = PlaybackVolumeController()..apply(1);
      var firstDone = false;

      controller.rampTemporaryGain(
        0,
        duration: const Duration(milliseconds: 120),
        steps: 6,
        onDone: () => firstDone = true,
      );
      await tester.pump(const Duration(milliseconds: 30));
      controller.rampTemporaryGain(
        1,
        duration: const Duration(milliseconds: 60),
        steps: 3,
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(firstDone, isFalse);
      expect(controller.temporaryGain, closeTo(1, 1e-9));
    });

    testWidgets('fadeOutToSilence reports completion', (tester) async {
      final controller = PlaybackVolumeController()..apply(1);

      final future = controller.fadeOutToSilence(
        const Duration(milliseconds: 60),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(await future, isTrue);
      expect(controller.temporaryGain, 0);
    });

    testWidgets('fadeOutToSilence returns false when interrupted', (
      tester,
    ) async {
      final controller = PlaybackVolumeController()..apply(1);

      final future = controller.fadeOutToSilence(
        const Duration(milliseconds: 120),
      );
      await tester.pump(const Duration(milliseconds: 20));
      // 用户中途又按了播放：取消淡出，音量回到用户设定。
      controller.clearTemporaryGain();
      await tester.pump(const Duration(milliseconds: 40));

      expect(await future, isFalse);
      expect(controller.temporaryGain, closeTo(1, 1e-9));
    });

    testWidgets('a zero duration snaps instead of scheduling', (tester) async {
      final controller = PlaybackVolumeController()..apply(1);

      controller.rampTemporaryGain(0, duration: Duration.zero, steps: 6);

      expect(controller.temporaryGain, 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.temporaryGain, 0);
    });
  });
}
