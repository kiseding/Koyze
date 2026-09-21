import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/equalizer_gain.dart';

void main() {
  test('空列表保持为空', () {
    expect(normalizeEqualizerGains(const <double>[]), isEmpty);
  });

  test('峰值不超过 0 dB 时原样返回拷贝', () {
    const source = <double>[-2, 0, -1];
    final normalized = normalizeEqualizerGains(source);
    expect(normalized, source);
    expect(identical(normalized, source), isFalse);
  });

  test('峰值大于 0 dB 时整体下移到 0', () {
    expect(
      normalizeEqualizerGains(const <double>[6, 4, 1, 0, 0]),
      const <double>[0, -2, -5, -6, -6],
    );
    expect(normalizeEqualizerGains(const <double>[-1, 3, 1]), const <double>[
      -4,
      0,
      -2,
    ]);
  });
}
