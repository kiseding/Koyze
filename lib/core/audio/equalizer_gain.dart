import 'dart:math' as math;

/// 把曲线整体下移，使最响的频段贴齐 0 dB。
///
/// Android `Equalizer` 没有限幅。多段同时正向增益（尤其是「低音增强」
/// 「高音增强」）会在频段交叠处削波，听感是音量突然变大并带电流声。
/// 响度应走系统音量，均衡器只塑形。
List<double> normalizeEqualizerGains(List<double> gains) {
  if (gains.isEmpty) return const <double>[];
  final peak = gains.reduce(math.max);
  if (peak <= 0) return List<double>.of(gains);
  return <double>[for (final gain in gains) gain - peak];
}
