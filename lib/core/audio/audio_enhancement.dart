import 'package:flutter/foundation.dart';

import 'audio_enhancement_factory_web.dart'
    if (dart.library.io) 'audio_enhancement_factory_native.dart'
    as impl;
import 'playback_engine.dart';

/// 除均衡器之外的音频增强项。
///
/// 这些能力全部建立在 mpv 的 `af` 链上，所以只要引擎是 mpv 就全平台可用。
/// 单独抽出来而不是塞进均衡器设置，是因为它们的语义不同：均衡器是「一条
/// 曲线」，这些是「几个独立开关」，两者的持久化键与界面分组也不一样。
@immutable
class AudioEnhancementSettings {
  const AudioEnhancementSettings({
    this.crossfeedEnabled = false,
    this.crossfeedStrength = 0.35,
    this.loudnessEnabled = false,
    this.limiterEnabled = true,
  });

  /// 交叉馈送：耳机听硬声像录音时缓解「头中效应」。
  final bool crossfeedEnabled;

  /// 交叉馈送强度（0~1）。越高声场越窄，0.35 是保守默认。
  final double crossfeedStrength;

  /// 响度均衡：把不同录音的音量拉平。
  final bool loudnessEnabled;

  /// 链尾限幅。
  ///
  /// 默认开启：均衡器和 Preamp 都可能产生正增益，没有限幅就是直接削波。
  /// 限幅器只在真的顶到天花板时才动作，正常素材听不出区别。
  final bool limiterEnabled;

  AudioEnhancementSettings copyWith({
    bool? crossfeedEnabled,
    double? crossfeedStrength,
    bool? loudnessEnabled,
    bool? limiterEnabled,
  }) => AudioEnhancementSettings(
    crossfeedEnabled: crossfeedEnabled ?? this.crossfeedEnabled,
    crossfeedStrength: crossfeedStrength ?? this.crossfeedStrength,
    loudnessEnabled: loudnessEnabled ?? this.loudnessEnabled,
    limiterEnabled: limiterEnabled ?? this.limiterEnabled,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'crossfeedEnabled': crossfeedEnabled,
    'crossfeedStrength': crossfeedStrength,
    'loudnessEnabled': loudnessEnabled,
    'limiterEnabled': limiterEnabled,
  };

  /// 解析持久化数据。字段缺失或类型不对时用默认值，不抛异常——
  /// 一份坏掉的设置不该让播放器起不来。
  factory AudioEnhancementSettings.fromJson(Map<String, dynamic> json) {
    double readDouble(String key, double fallback) {
      final value = json[key];
      if (value is num && value.isFinite) return value.toDouble();
      return fallback;
    }

    bool readBool(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    return AudioEnhancementSettings(
      crossfeedEnabled: readBool('crossfeedEnabled', false),
      crossfeedStrength: readDouble('crossfeedStrength', 0.35).clamp(0.0, 1.0),
      loudnessEnabled: readBool('loudnessEnabled', false),
      limiterEnabled: readBool('limiterEnabled', true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioEnhancementSettings &&
      other.crossfeedEnabled == crossfeedEnabled &&
      other.crossfeedStrength == crossfeedStrength &&
      other.loudnessEnabled == loudnessEnabled &&
      other.limiterEnabled == limiterEnabled;

  @override
  int get hashCode => Object.hash(
    crossfeedEnabled,
    crossfeedStrength,
    loudnessEnabled,
    limiterEnabled,
  );
}

/// 把增强项写进播放引擎的最小接口。
///
/// 和 [EqualizerBridge] 分开是因为它的实现只有一个（mpv 的 `af` 链），
/// 不需要按平台分叉；Web 上没有 mpv，拿到的就是空实现。
abstract class AudioEnhancementSink {
  /// 是否真的能生效。界面据此决定是否禁用开关。
  bool get isSupported;

  /// 立即施加。重复调用同一份设置必须是幂等的。
  void apply(AudioEnhancementSettings settings);
}

/// 空实现：Web 与「引擎不是 mpv」时使用。
class NoopAudioEnhancementSink implements AudioEnhancementSink {
  const NoopAudioEnhancementSink();

  @override
  bool get isSupported => false;

  @override
  void apply(AudioEnhancementSettings settings) {}
}

/// 按当前引擎创建增强项写入端。
///
/// 类型判断必须留在原生侧：这个文件在 Web 编译图里是可达的（设置页会
/// 读它），一旦直接 import `mpv_engine.dart`，dart2js 就会因为 FFI 的
/// `external` 声明直接失败。和 `mpv_equalizer_factory` 是同一套处理。
AudioEnhancementSink createAudioEnhancementSink(PlaybackEngine? engine) =>
    impl.buildAudioEnhancementSink(engine);
