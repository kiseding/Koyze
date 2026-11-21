import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_spectrum_factory_web.dart'
    if (dart.library.io) 'audio_spectrum_factory_native.dart'
    as impl;
import 'playback_engine.dart';

/// 一帧实时频谱。
///
/// 刻意不暴露 mpv 的 `FftFrame`：`package:mpv_audio_kit` 里全是 `dart:ffi`
/// 的 `external` 声明，一旦这个类型出现在 Web 编译图里，dart2js 就会直接
/// 失败（`test/build_configuration_test.dart` 钉着这条边界）。因此把需要的
/// 那部分——一个归一化到 0~1 的频段数组——复制成本类型再往上传。
@immutable
class SpectrumFrame {
  const SpectrumFrame({
    required this.bands,
    this.bandLowHz = 20,
    this.bandHighHz = 20000,
  });

  /// 每个频段的幅值，均归一化到 `[0, 1]`。
  ///
  /// mpv 侧已经做过对数分频、dB 裁剪与「上升快下降慢」的平滑，画的时候
  /// 不需要再平滑一次。
  final List<double> bands;

  /// 频段轴的上下边界，用于绘制刻度或频段标注。
  final double bandLowHz;
  final double bandHighHz;

  /// 是否包含任何有意义的能量。全零帧意味着静音，界面据此停下动画
  /// 而不是继续按帧重绘。
  bool get isSilent {
    for (final value in bands) {
      if (value > 0.004) return false;
    }
    return true;
  }
}

/// 实时频谱的来源。
///
/// Web 与 just_audio 回退路径拿不到 mpv 的频谱管线，[available] 为 false，
/// 界面据此整块不渲染——这是「其它元素不能动」的前提：没有数据时不能留
/// 一块空白占着布局。
abstract class AudioSpectrumSource {
  /// 当前引擎是否能提供实时频谱。
  bool get available;

  /// 频谱帧流。惰性：订阅时引擎才开始算 FFT，取消后即停。
  ///
  /// 不可用时是空流而不是抛异常，让调用方只写一条监听路径。
  Stream<SpectrumFrame> get frames;

  /// 停掉底层 FFT 管线。离开播放页时调用，避免在后台白跑。
  Future<void> dispose();
}

/// 空实现：Web 与「引擎不是 mpv」时使用。
class NoopAudioSpectrumSource implements AudioSpectrumSource {
  const NoopAudioSpectrumSource();

  @override
  bool get available => false;

  @override
  Stream<SpectrumFrame> get frames => const Stream<SpectrumFrame>.empty();

  @override
  Future<void> dispose() async {}
}

/// 按当前引擎创建频谱来源。
///
/// 类型判断必须留在原生侧，理由同 `audio_enhancement.dart`：这个文件在
/// Web 编译图里可达（播放页会读它），直接 import `mpv_engine.dart` 就会
/// 把 FFI 拖进 dart2js。
AudioSpectrumSource createAudioSpectrumSource(PlaybackEngine? engine) =>
    impl.buildAudioSpectrumSource(engine);