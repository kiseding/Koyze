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

  bool get isCustom => presetId == kCustomPresetId;

  bool get isAutoEq => presetId == kAutoEqPresetId;

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
  }) => EqualizerSettings(
    enabled: enabled ?? this.enabled,
    presetId: presetId ?? this.presetId,
    gains: gains ?? this.gains,
    autoEqName: autoEqName ?? this.autoEqName,
    autoEqCurve: autoEqCurve ?? this.autoEqCurve,
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
    return EqualizerSettings(
      enabled: json['enabled'] == true,
      presetId: rawPreset is String && rawPreset.isNotEmpty
          ? rawPreset
          : kDefaultPresetId,
      gains: List<double>.unmodifiable(gains),
      autoEqName: json['autoEqName']?.toString(),
      autoEqCurve: List<EqualizerControlPoint>.unmodifiable(curve),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EqualizerSettings &&
      other.enabled == enabled &&
      other.presetId == presetId &&
      other.autoEqName == autoEqName &&
      listEquals(other.gains, gains) &&
      listEquals(other.autoEqCurve, autoEqCurve);

  @override
  int get hashCode => Object.hash(
    enabled,
    presetId,
    autoEqName,
    Object.hashAll(gains),
    Object.hashAll(autoEqCurve),
  );
}

/// 按预设曲线采样出频段增益；未知预设（含自定义）视为原声。
List<double> gainsForPreset(String presetId, List<double> centerFrequencies) {
  final preset = equalizerPresetById(presetId);
  if (preset == null) return List<double>.filled(centerFrequencies.length, 0);
  return preset.gainsFor(centerFrequencies);
}
