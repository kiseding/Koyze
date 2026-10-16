import 'dart:math' as math;

/// 单段允许的最高增益。
///
/// Android 图形均衡器相邻段会叠在一起。整条曲线先对齐平均响度，再把
/// 最高的一段压到这个天花板，避免一开均衡器整首变小，也避免正向增益
/// 叠到削波、带电流声。
const double kEqualizerPeakCeilingDb = 3;

/// 把曲线调成响度接近原声，同时峰值不超过 [kEqualizerPeakCeilingDb]。
///
/// 先减去平均值，加减抵消，整首不大声也不变小；最高段仍超过天花板时，
/// 再整体下移刚好够用的量。结果四舍五入到 0.1 dB。
List<double> normalizeEqualizerGains(List<double> gains) {
  if (gains.isEmpty) return const <double>[];
  var sum = 0.0;
  for (final gain in gains) {
    sum += gain;
  }
  final mean = sum / gains.length;
  final centered = <double>[for (final gain in gains) gain - mean];
  final peak = centered.reduce(math.max);
  final shift = math.max(0.0, peak - kEqualizerPeakCeilingDb);
  return <double>[for (final gain in centered) _roundTenth(gain - shift)];
}

double _roundTenth(double value) => (value * 10).roundToDouble() / 10;
