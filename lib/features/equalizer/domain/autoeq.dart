import 'dart:math' as math;

import 'equalizer_preset.dart';

/// AutoEQ 参数均衡器里的一个 biquad。
///
/// AutoEQ 发布的 `ParametricEQ.txt` 长这样：
/// ```
/// Preamp: -6.2 dB
/// Filter 1: ON PK Fc 105 Hz Gain 5.5 dB Q 0.70
/// Filter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
/// ```
class AutoEqFilter {
  const AutoEqFilter({
    required this.type,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    this.enabled = true,
  });

  /// `PK` / `LS` / `HS` / `LSC` / `HSC` / 数字（老格式的 peaking）。
  final String type;
  final double frequencyHz;
  final double gainDb;
  final double q;
  final bool enabled;

  bool get isLowShelf => type.startsWith('LS');
  bool get isHighShelf => type.startsWith('HS');

  /// 该滤波器在 [frequency] 处的幅度响应（dB）。
  ///
  /// 用 RBJ Audio EQ Cookbook 的系数，在 48 kHz 下求值。采样率只影响极高频
  /// （接近 Nyquist 的部分），而我们最后只在设备的中心频率上取值，误差可以忽略。
  double gainAt(double frequency) {
    if (!enabled || gainDb == 0) return 0;
    const sampleRate = 48000.0;
    final f0 = frequencyHz.clamp(10.0, sampleRate / 2 - 100);
    final fc = frequency.clamp(1.0, sampleRate / 2 - 100);
    final a = math.pow(10, gainDb / 40).toDouble();
    final w0 = 2 * math.pi * f0 / sampleRate;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final qq = q <= 0 ? 0.707 : q;
    final alpha = sinW0 / (2 * qq);

    late final double b0, b1, b2, a0, a1, a2;
    if (isLowShelf) {
      final sqrtA = math.sqrt(a);
      final beta = 2 * sqrtA * alpha;
      b0 = a * ((a + 1) - (a - 1) * cosW0 + beta);
      b1 = 2 * a * ((a - 1) - (a + 1) * cosW0);
      b2 = a * ((a + 1) - (a - 1) * cosW0 - beta);
      a0 = (a + 1) + (a - 1) * cosW0 + beta;
      a1 = -2 * ((a - 1) + (a + 1) * cosW0);
      a2 = (a + 1) + (a - 1) * cosW0 - beta;
    } else if (isHighShelf) {
      final sqrtA = math.sqrt(a);
      final beta = 2 * sqrtA * alpha;
      b0 = a * ((a + 1) + (a - 1) * cosW0 + beta);
      b1 = -2 * a * ((a - 1) + (a + 1) * cosW0);
      b2 = a * ((a + 1) + (a - 1) * cosW0 - beta);
      a0 = (a + 1) - (a - 1) * cosW0 + beta;
      a1 = 2 * ((a - 1) - (a + 1) * cosW0);
      a2 = (a + 1) - (a - 1) * cosW0 - beta;
    } else {
      // 默认按 peaking 处理：AutoEQ 里绝大多数滤波器都是这个类型。
      b0 = 1 + alpha * a;
      b1 = -2 * cosW0;
      b2 = 1 - alpha * a;
      a0 = 1 + alpha / a;
      a1 = -2 * cosW0;
      a2 = 1 - alpha / a;
    }

    final w = 2 * math.pi * fc / sampleRate;
    final cosW = math.cos(w);
    final sinW = math.sin(w);
    final cos2W = math.cos(2 * w);
    final sin2W = math.sin(2 * w);
    // H(e^{jw}) = (b0 + b1 e^{-jw} + b2 e^{-2jw}) / (a0 + a1 e^{-jw} + a2 e^{-2jw})
    final numeratorReal = b0 + b1 * cosW + b2 * cos2W;
    final numeratorImag = -(b1 * sinW + b2 * sin2W);
    final denominatorReal = a0 + a1 * cosW + a2 * cos2W;
    final denominatorImag = -(a1 * sinW + a2 * sin2W);
    final numerator = math.sqrt(
      numeratorReal * numeratorReal + numeratorImag * numeratorImag,
    );
    final denominator = math.sqrt(
      denominatorReal * denominatorReal + denominatorImag * denominatorImag,
    );
    if (denominator == 0) return 0;
    return 20 * math.log(numerator / denominator) / math.ln10;
  }
}

/// 一条解析好的 AutoEQ 曲线。
class AutoEqProfile {
  const AutoEqProfile({
    required this.name,
    required this.curve,
    required this.preampDb,
    this.filters = const <AutoEqFilter>[],
  });

  final String name;

  /// 可直接喂给 [EqualizerPreset] 的控制点（频率升序）。
  final List<EqualizerControlPoint> curve;

  /// AutoEQ 自带的预放大，通常是负值，用来给叠加后的峰值留余量。
  final double preampDb;

  final List<AutoEqFilter> filters;

  EqualizerPreset toPreset() =>
      EqualizerPreset(id: 'autoeq', label: name, curve: curve);
}

/// 解析 AutoEQ 文件。无法识别时返回 null。
///
/// 同时支持两种格式：
/// * `ParametricEQ.txt`（Filter 行，需要算 biquad 响应）
/// * `GraphicEQ.txt`（`GraphicEQ: 20 -3.1; 21 -3.0; ...`，直接是采样点）
AutoEqProfile? parseAutoEq(String content, {required String name}) {
  final preampMatch = RegExp(
    r'Preamp\s*:\s*(-?[0-9.]+)\s*dB',
    caseSensitive: false,
  ).firstMatch(content);
  final preamp = double.tryParse(preampMatch?.group(1) ?? '') ?? 0;

  final filters = <AutoEqFilter>[];
  final filterPattern = RegExp(
    r'Filter\s*\d+\s*:\s*(ON|OFF)\s+([A-Za-z]+|\d+)\s+Fc\s+([0-9.]+)\s*Hz'
    r'\s+Gain\s+(-?[0-9.]+)\s*dB\s+Q\s+([0-9.]+)',
    caseSensitive: false,
  );
  for (final match in filterPattern.allMatches(content)) {
    filters.add(
      AutoEqFilter(
        enabled: match.group(1)!.toUpperCase() == 'ON',
        type: match.group(2)!.toUpperCase(),
        frequencyHz: double.parse(match.group(3)!),
        gainDb: double.parse(match.group(4)!),
        q: double.parse(match.group(5)!),
      ),
    );
  }
  if (filters.isNotEmpty) {
    return AutoEqProfile(
      name: name,
      curve: _sampleCurve(
        (frequency) => _sumFilterGains(filters, frequency) + preamp,
      ),
      preampDb: preamp,
      filters: filters,
    );
  }

  final graphicMatch = RegExp(
    r'GraphicEQ\s*:\s*([^\n\r]+)',
    caseSensitive: false,
  ).firstMatch(content);
  if (graphicMatch != null) {
    final points = <EqualizerControlPoint>[];
    for (final part in graphicMatch.group(1)!.split(';')) {
      final pieces = part.trim().split(RegExp(r'\s+'));
      if (pieces.length < 2) continue;
      final frequency = double.tryParse(pieces[0]);
      final gain = double.tryParse(pieces[1]);
      if (frequency == null || gain == null) continue;
      if (frequency <= 0) continue;
      points.add(EqualizerControlPoint(frequency, gain + preamp));
    }
    if (points.length >= 2) {
      points.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
      return AutoEqProfile(
        name: name,
        curve: List<EqualizerControlPoint>.unmodifiable(points),
        preampDb: preamp,
      );
    }
  }
  return null;
}

double _sumFilterGains(List<AutoEqFilter> filters, double frequency) {
  var total = 0.0;
  for (final filter in filters) {
    total += filter.gainAt(frequency);
  }
  return total;
}

/// 在 20 Hz~20 kHz 之间按对数均匀取 48 个点。
///
/// 取这么多点是因为 `EqualizerPreset.gainAt` 在对数频率上做线性插值：
/// 点足够密时，插值误差远小于设备 ±12 dB 的量化步进。
List<EqualizerControlPoint> _sampleCurve(double Function(double) gainAt) {
  const count = 48;
  const minFrequency = 20.0;
  const maxFrequency = 20000.0;
  final ratio = math.pow(maxFrequency / minFrequency, 1 / (count - 1));
  return List<EqualizerControlPoint>.unmodifiable([
    for (var i = 0; i < count; i++)
      EqualizerControlPoint(
        minFrequency * math.pow(ratio, i).toDouble(),
        gainAt(minFrequency * math.pow(ratio, i).toDouble()),
      ),
  ]);
}
