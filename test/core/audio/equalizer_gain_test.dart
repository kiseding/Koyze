import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/equalizer_gain.dart';

void main() {
  test('空列表保持为空', () {
    expect(normalizeEqualizerGains(const <double>[]), isEmpty);
  });

  test('全 0 保持为 0', () {
    expect(normalizeEqualizerGains(const <double>[0, 0, 0]), const <double>[
      0,
      0,
      0,
    ]);
  });

  test('平均响度对齐到 0，峰值不超过天花板', () {
    final normalized = normalizeEqualizerGains(const <double>[-2, 0, -1]);
    expect(normalized, const <double>[-1, 1, 0]);
    expect(
      normalized.reduce((a, b) => a > b ? a : b),
      lessThanOrEqualTo(kEqualizerPeakCeilingDb),
    );
  });

  test('超过天花板时只下移超出的部分', () {
    expect(
      normalizeEqualizerGains(const <double>[6, 4, 1, 0, 0]),
      const <double>[3, 1, -2, -3, -3],
    );
    expect(normalizeEqualizerGains(const <double>[-1, 3, 1]), const <double>[
      -2,
      2,
      0,
    ]);
  });
}
