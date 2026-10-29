import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/settings/presentation/settings_notifiers.dart';

void main() {
  group('normalizePlaybackSpeed', () {
    test('snaps to the nearest supported step', () {
      expect(normalizePlaybackSpeed(0.52), 0.5);
      expect(normalizePlaybackSpeed(0.99), 1.0);
      expect(normalizePlaybackSpeed(1.4), 1.5);
      expect(normalizePlaybackSpeed(1.62), 1.5);
      expect(normalizePlaybackSpeed(1.9), 2.0);
    });

    test('clamps out-of-range and non-finite input to 1.0', () {
      expect(normalizePlaybackSpeed(0), 1.0);
      expect(normalizePlaybackSpeed(-2), 1.0);
      expect(normalizePlaybackSpeed(double.nan), 1.0);
      // 超出上界的值吸附到最大档位，而不是回到 1.0。
      expect(normalizePlaybackSpeed(5), 2.0);
    });
  });

  group('playbackSpeedLabel', () {
    test('formats whole and fractional steps', () {
      expect(playbackSpeedLabel(1.0), '1.0×');
      expect(playbackSpeedLabel(1.25), '1.25×');
      expect(playbackSpeedLabel(0.75), '0.75×');
      expect(playbackSpeedLabel(2.0), '2.0×');
    });

    test('never shows more than two decimals', () {
      expect(playbackSpeedLabel(1.2499), '1.25×');
    });
  });

  group('normalizePrecacheCount', () {
    test('snaps to 5 / 10 / 20', () {
      expect(normalizePrecacheCount(0), 5);
      expect(normalizePrecacheCount(6), 5);
      expect(normalizePrecacheCount(9), 10);
      // 正中相等时取较小的一档：宁可少下几首。
      expect(normalizePrecacheCount(15), 10);
      expect(normalizePrecacheCount(16), 20);
      expect(normalizePrecacheCount(1000), 20);
    });
  });

  test('every playback speed step is labelled distinctly', () {
    final labels = <String>{};
    for (final step in kPlaybackSpeedSteps) {
      labels.add(playbackSpeedLabel(step));
    }
    expect(labels, hasLength(kPlaybackSpeedSteps.length));
  });
}
