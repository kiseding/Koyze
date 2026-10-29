import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';

void main() {
  group('normalizePitchSemitones', () {
    test('keeps two decimals instead of snapping to half steps', () {
      expect(normalizePitchSemitones(0.2), 0.2);
      expect(normalizePitchSemitones(1.24), 1.24);
      expect(normalizePitchSemitones(1.234), 1.23);
      expect(normalizePitchSemitones(-2.345), -2.35);
    });

    test('clamps to one octave either way', () {
      expect(normalizePitchSemitones(40), 12);
      expect(normalizePitchSemitones(-40), -12);
    });

    test('non-finite input falls back to original pitch', () {
      expect(normalizePitchSemitones(double.nan), 0);
      expect(normalizePitchSemitones(double.infinity), 0);
      expect(normalizePitchSemitones(double.negativeInfinity), 0);
    });
  });

  group('pitchFactorForSemitones', () {
    test('0 semitones is unity', () {
      expect(pitchFactorForSemitones(0), closeTo(1, 1e-12));
    });

    test('12 semitones is one octave up', () {
      expect(pitchFactorForSemitones(12), closeTo(2, 1e-9));
      expect(pitchFactorForSemitones(-12), closeTo(0.5, 1e-9));
    });

    test('each semitone is the twelfth root of two', () {
      expect(
        pitchFactorForSemitones(1),
        closeTo(math.pow(2, 1 / 12).toDouble(), 1e-9),
      );
      expect(pitchFactorForSemitones(7), closeTo(1.4983, 1e-3)); // 纯五度
    });

    test('432 Hz tuning sits just under a third of a semitone down', () {
      final semitones = 12 * (math.log(kPitchFactor432Hz) / math.ln2);
      expect(semitones, closeTo(-0.3177, 1e-3));
      // 存进去会保留两位小数（-0.32），换算回来是 431.94Hz：0.02% 的偏差，
      // 远小于人耳能分辨的 0.3%（约 5 音分）。
      expect(pitchFactorForSemitones(semitones), closeTo(432 / 440, 2e-4));
    });
  });

  group('pitchSemitonesLabel', () {
    test('zero shows as plain 0', () {
      expect(pitchSemitonesLabel(0), '0');
    });

    test('positive values carry a plus sign', () {
      expect(pitchSemitonesLabel(2), '+2');
      expect(pitchSemitonesLabel(0.5), '+0.5');
      expect(pitchSemitonesLabel(1.5), '+1.5');
    });

    test('negative values keep their minus sign', () {
      expect(pitchSemitonesLabel(-3), '-3');
      expect(pitchSemitonesLabel(-0.5), '-0.5');
      expect(pitchSemitonesLabel(-0.32), '-0.32');
    });

    test('trailing zeros are trimmed, not rounded away', () {
      expect(pitchSemitonesLabel(1.20), '+1.2');
      expect(pitchSemitonesLabel(2.00), '+2');
      expect(pitchSemitonesLabel(1.4), '+1.4');
      expect(pitchSemitonesLabel(-0.2), '-0.2');
    });
  });
}
