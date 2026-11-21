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

  test('天花板留得住预设的动态范围', () {
    // 预设曲线本身有 10 dB 上下的动态范围。天花板若只有 3 dB，几乎所有
    // 预设都会被压进 6 dB 的窗口里，彼此只差一两个 dB —— 用户听到的就是
    // 「换了预设没区别」。这条断言守住天花板不再被悄悄调小。
    expect(kEqualizerPeakCeilingDb, greaterThanOrEqualTo(5));

    // 十段典型曲线（含 ±5 dB 的两端）都不该被二次削峰。
    const curves = <List<double>>[
      <double>[4, 2, -1, 2, -7],
      <double>[5, 1, -5, 2, -3],
      <double>[-5, -3, 5, 3, 0],
      <double>[-6, -5, -1, 4, 5],
    ];
    for (final curve in curves) {
      expect(
        normalizeEqualizerGains(curve),
        <double>[for (final gain in curve) gain],
        reason: '$curve 的均值已经是 0，对齐应当不改变任何一段',
      );
    }
  });

  test('超过天花板时只下移超出的部分', () {
    // 均值 3 → 对齐后峰值 7，超出 5 的 2 dB 由整条曲线一起下移。
    expect(
      normalizeEqualizerGains(const <double>[10, 4, 1, 0, 0]),
      const <double>[5, -1, -4, -5, -5],
    );
    // 峰值本来就在天花板内，一点不动。
    expect(normalizeEqualizerGains(const <double>[-1, 3, 1]), const <double>[
      -2,
      2,
      0,
    ]);
  });
}