import 'package:flutter/foundation.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/features/equalizer/domain/equalizer_preset.dart';

/// 任一频段被手动拖动后即为「自定义」预设。
const String kCustomPresetId = 'custom';

/// 从 AutoEQ 文件导入的曲线。它和内置预设的区别是曲线随设置一起持久化：
/// 用户导入的耳机补偿不属于「内置数据」，升级不能把它清掉。
const String kAutoEqPresetId = 'autoeq';

/// 播放器还没激活过时界面使用的兜底布局。
///
/// 播放器只有在载入过音频源之后才会连上平台，此时设备真实的频段参数
/// 还拿不到。60 / 230 / 910 / 3600 / 14000 Hz 是 Android 上最常见的 5 段
/// 划分，增益范围取常见的 ±12 dB；真实布局到手后会立即替换。
const EqualizerBandLayout kFallbackEqualizerLayout = EqualizerBandLayout(
  minDecibels: -12,
  maxDecibels: 12,
  centerFrequencies: <double>[60, 230, 910, 3600, 14000],
);

/// 均衡器设置。
@immutable
class EqualizerSettings {
  const EqualizerSettings({
    this.enabled = false,
    this.presetId = kDefaultPresetId,
    this.gains = const <double>[],
    this.autoEqName,
    this.autoEqCurve = const <EqualizerControlPoint>[],
    this.autoEqBiquads = const <AutoEqBiquad>[],
    this.preampDb = 0,
  });

  /// 总开关。
  final bool enabled;

  /// 当前预设 id；[kCustomPresetId] 表示手动调过频段。
  final String presetId;

  /// 各频段增益（dB），按设备频段顺序；段数与设备不一致时会被忽略。
  final List<double> gains;

  /// 导入的 AutoEQ 方案名（耳机型号 + 目标曲线）。
  final String? autoEqName;

  /// 导入的 AutoEQ 曲线控制点；仅在 [presetId] 为 [kAutoEqPresetId] 时使用。
  final List<EqualizerControlPoint> autoEqCurve;

  /// AutoEQ 的原始滤波器（带各自的频率与 Q 值）。
  ///
  /// 和 [autoEqCurve] 是同一份数据的两种形态：曲线用于画图与降级到固定
  /// 频段，滤波器用于在 mpv 上按原样精确下发。两者都存是为了让「换到
  /// just_audio 回退路径」时仍有可用的近似。
  final List<AutoEqBiquad> autoEqBiquads;

  /// AutoEQ 文件自带的 Preamp（dB，通常为负）。
  ///
  /// 以前这个值被丢掉，改用「把曲线均值归零」来近似响度对齐。两者不等价：
  /// Preamp 是作者按峰值算的余量，均值归零是统计量，会漏掉局部峰。
  final double preampDb;

  bool get isCustom => presetId == kCustomPresetId;

  bool get isAutoEq => presetId == kAutoEqPresetId;

  /// 是否走参数均衡（AutoEQ 且原始滤波器可用）。
  bool get usesParametricAutoEq => isAutoEq && autoEqBiquads.isNotEmpty;

  /// 界面展示用的预设名。
  String get presetLabel {
    if (isAutoEq) {
      final name = autoEqName?.trim();
      return name == null || name.isEmpty ? 'AutoEQ' : name;
    }
    return equalizerPresetLabel(presetId);
  }

  EqualizerSettings copyWith({
    bool? enabled,
    String? presetId,
    List<double>? gains,
    String? autoEqName,
    List<EqualizerControlPoint>? autoEqCurve,
    List<AutoEqBiquad>? autoEqBiquads,
    double? preampDb,
  }) => EqualizerSettings(
    enabled: enabled ?? this.enabled,
    presetId: presetId ?? this.presetId,
    gains: gains ?? this.gains,
    autoEqName: autoEqName ?? this.autoEqName,
    autoEqCurve: autoEqCurve ?? this.autoEqCurve,
    autoEqBiquads: autoEqBiquads ?? this.autoEqBiquads,
    preampDb: preampDb ?? this.preampDb,
  );

  /// 按 [layout] 解析实际要施加的增益。
  ///
  /// 命名预设始终按当前曲线重新采样（含响度对齐），这样旧版本存下来的
  /// 正向增益不会继续把整轨抬响。自定义且段数一致时沿用保存值，
  /// 段数对不上则视为原声。
  List<double> gainsFor(EqualizerBandLayout layout) {
    if (isAutoEq) {
      if (autoEqCurve.length < 2) {
        return List<double>.filled(layout.bandCount, 0);
      }
      return EqualizerPreset(
        id: kAutoEqPresetId,
        label: autoEqName ?? 'AutoEQ',
        curve: autoEqCurve,
      ).gainsFor(layout.centerFrequencies);
    }
    if (isCustom) {
      if (gains.length == layout.bandCount) return gains;
      return List<double>.filled(layout.bandCount, 0);
    }
    return gainsForPreset(presetId, layout.centerFrequencies);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'preset': presetId,
    'gains': gains,
    if (autoEqName != null) 'autoEqName': autoEqName,
    if (autoEqCurve.isNotEmpty)
      'autoEqCurve': <List<double>>[
        for (final point in autoEqCurve) [point.frequencyHz, point.gainDb],
      ],
    if (autoEqBiquads.isNotEmpty)
      'autoEqBiquads': <Map<String, dynamic>>[
        for (final biquad in autoEqBiquads)
          <String, dynamic>{
            'type': biquad.type,
            'f': biquad.frequencyHz,
            'g': biquad.gainDb,
            'q': biquad.q,
            if (!biquad.enabled) 'off': true,
          },
      ],
    if (preampDb != 0) 'preampDb': preampDb,
  };

  static EqualizerSettings fromJson(Map<String, dynamic> json) {
    final rawGains = json['gains'];
    final gains = <double>[];
    if (rawGains is List) {
      for (final item in rawGains) {
        if (item is num) gains.add(item.toDouble());
      }
    }
    final curve = <EqualizerControlPoint>[];
    final rawCurve = json['autoEqCurve'];
    if (rawCurve is List) {
      for (final item in rawCurve) {
        if (item is List && item.length >= 2) {
          final frequency = (item[0] as num?)?.toDouble();
          final gain = (item[1] as num?)?.toDouble();
          if (frequency == null || gain == null || frequency <= 0) continue;
          curve.add(EqualizerControlPoint(frequency, gain));
        }
      }
    }
    final rawPreset = json['preset'];
    final biquads = <AutoEqBiquad>[];
    final rawBiquads = json['autoEqBiquads'];
    if (rawBiquads is List) {
      for (final item in rawBiquads) {
        if (item is! Map) continue;
        final type = item['type']?.toString();
        final frequency = (item['f'] as num?)?.toDouble();
        final gain = (item['g'] as num?)?.toDouble();
        final q = (item['q'] as num?)?.toDouble();
        if (type == null || frequency == null || gain == null) continue;
        if (!frequency.isFinite || frequency <= 0) continue;
        if (!gain.isFinite) continue;
        biquads.add(
          AutoEqBiquad(
            type: type,
            frequencyHz: frequency,
            gainDb: gain,
            q: q != null && q.isFinite && q > 0 ? q : 0.707,
            enabled: item['off'] != true,
          ),
        );
      }
    }
    final rawPreamp = (json['preampDb'] as num?)?.toDouble();
    return EqualizerSettings(
      enabled: json['enabled'] == true,
      presetId: rawPreset is String && rawPreset.isNotEmpty
          ? rawPreset
          : kDefaultPresetId,
      gains: List<double>.unmodifiable(gains),
      autoEqName: json['autoEqName']?.toString(),
      autoEqCurve: List<EqualizerControlPoint>.unmodifiable(curve),
      autoEqBiquads: List<AutoEqBiquad>.unmodifiable(biquads),
      preampDb: rawPreamp != null && rawPreamp.isFinite ? rawPreamp : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EqualizerSettings &&
      other.enabled == enabled &&
      other.presetId == presetId &&
      other.autoEqName == autoEqName &&
      other.preampDb == preampDb &&
      listEquals(other.gains, gains) &&
      listEquals(other.autoEqCurve, autoEqCurve) &&
      listEquals(other.autoEqBiquads, autoEqBiquads);

  @override
  int get hashCode => Object.hash(
    enabled,
    presetId,
    autoEqName,
    preampDb,
    Object.hashAll(gains),
    Object.hashAll(autoEqCurve),
    Object.hashAll(autoEqBiquads),
  );
}

/// 按预设曲线采样出频段增益；未知预设（含自定义）视为原声。
List<double> gainsForPreset(String presetId, List<double> centerFrequencies) {
  final preset = equalizerPresetById(presetId);
  if (preset == null) return List<double>.filled(centerFrequencies.length, 0);
  return preset.gainsFor(centerFrequencies);
}
