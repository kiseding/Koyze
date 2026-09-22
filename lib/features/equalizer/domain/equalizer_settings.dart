import 'package:flutter/foundation.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/features/equalizer/domain/equalizer_preset.dart';

/// 任一频段被手动拖动后即为「自定义」预设。
const String kCustomPresetId = 'custom';

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
  });

  /// 总开关。
  final bool enabled;

  /// 当前预设 id；[kCustomPresetId] 表示手动调过频段。
  final String presetId;

  /// 各频段增益（dB），按设备频段顺序；段数与设备不一致时会被忽略。
  final List<double> gains;

  bool get isCustom => presetId == kCustomPresetId;

  /// 界面展示用的预设名。
  String get presetLabel => equalizerPresetLabel(presetId);

  EqualizerSettings copyWith({
    bool? enabled,
    String? presetId,
    List<double>? gains,
  }) => EqualizerSettings(
    enabled: enabled ?? this.enabled,
    presetId: presetId ?? this.presetId,
    gains: gains ?? this.gains,
  );

  /// 按 [layout] 解析实际要施加的增益。
  ///
  /// 命名预设始终按当前曲线重新采样（含响度对齐），这样旧版本存下来的
  /// 正向增益不会继续把整轨抬响。自定义且段数一致时沿用保存值，
  /// 段数对不上则视为原声。
  List<double> gainsFor(EqualizerBandLayout layout) {
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
  };

  static EqualizerSettings fromJson(Map<String, dynamic> json) {
    final rawGains = json['gains'];
    final gains = <double>[];
    if (rawGains is List) {
      for (final item in rawGains) {
        if (item is num) gains.add(item.toDouble());
      }
    }
    final rawPreset = json['preset'];
    return EqualizerSettings(
      enabled: json['enabled'] == true,
      presetId: rawPreset is String && rawPreset.isNotEmpty
          ? rawPreset
          : kDefaultPresetId,
      gains: List<double>.unmodifiable(gains),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EqualizerSettings &&
      other.enabled == enabled &&
      other.presetId == presetId &&
      listEquals(other.gains, gains);

  @override
  int get hashCode => Object.hash(enabled, presetId, Object.hashAll(gains));
}

/// 按预设曲线采样出频段增益；未知预设（含自定义）视为原声。
List<double> gainsForPreset(String presetId, List<double> centerFrequencies) {
  final preset = equalizerPresetById(presetId);
  if (preset == null) return List<double>.filled(centerFrequencies.length, 0);
  return preset.gainsFor(centerFrequencies);
}
