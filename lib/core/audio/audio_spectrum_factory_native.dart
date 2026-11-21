import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'audio_spectrum.dart';
import 'mpv_engine.dart';
import 'playback_engine.dart';

/// 原生侧的工厂。
///
/// 只有引擎真的是 mpv 才有 FFT 管线可订阅。just_audio 没有任何等价的
/// 频谱能力（它的 `audio_session` 不暴露采样），因此返回空实现让播放页
/// 整块不渲染，而不是显示一条永远不动的空条。
AudioSpectrumSource buildAudioSpectrumSource(PlaybackEngine? engine) {
  if (engine is MpvEngine) return MpvAudioSpectrumSource(engine.rawPlayer);
  return const NoopAudioSpectrumSource();
}

/// 从 mpv 的 `stream.fft` 取实时频谱。
///
/// 数据在音频输出端采集，**位于效果链之后**——用户听到什么，频谱就是什么。
/// 调了均衡器、Preamp、限幅，这里的形状会立刻跟着变，正好和均衡器页的
/// 曲线互相印证。
class MpvAudioSpectrumSource implements AudioSpectrumSource {
  MpvAudioSpectrumSource(this._player);

  final mpv.Player _player;

  /// 已投递出去的订阅。持有它是为了在 [dispose] 时明确取消——
  /// `stream.fft` 是惰性管线，最后一个订阅取消后 FFT 才会停，光靠
  /// 宿主 widget 被回收并不保证这一点（播放页在导航栈里常驻）。
  StreamSubscription<mpv.FftFrame>? _subscription;
  StreamController<SpectrumFrame>? _controller;
  bool _configured = false;
  bool _disposed = false;

  @override
  bool get available => !_disposed;

  @override
  Stream<SpectrumFrame> get frames {
    if (_disposed) return const Stream<SpectrumFrame>.empty();
    final existing = _controller;
    if (existing != null) return existing.stream;

    // 单订阅广播包一层：多个消费方（例如以后歌词页也要画）不会各自
    // 触发一条 mpv 订阅，也不会因为其中一方先取消就把另一方的流掐掉。
    final controller = StreamController<SpectrumFrame>.broadcast();
    _controller = controller;
    _configure();

    _subscription = _player.stream.fft.listen(
      (frame) {
        final bands = frame.bands;
        final values = List<double>.filled(bands.length, 0, growable: false);
        for (var i = 0; i < bands.length; i++) {
          final value = bands[i];
          values[i] = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
        }
        controller.add(
          SpectrumFrame(
            bands: values,
            bandLowHz: frame.bandLowHz,
            bandHighHz: frame.bandHighHz,
          ),
        );
      },
      // 引擎销毁、切到 just_audio 时流会关掉。这里不让错误冒到界面：
      // 频谱是装饰，挂了就静默停住，不该影响播放。
      onError: (_) {},
      cancelOnError: false,
    );
    return controller.stream;
  }

  /// 把管线配置成适合播放页的一条窄条。
  ///
  /// 64 段是 mpv 的默认值，正好够一条几百像素宽的条用；`fftSize` 保持
  /// 2048（30 Hz 分辨率下能分离开底鼓与 sub-bass，延迟仍在 A/V 同步阈值
  /// 内）。`emitInterval` 沿用 33ms ≈ 30fps，和 Flutter 的帧预算对齐。
  void _configure() {
    if (_configured) return;
    _configured = true;
    // 失败不抛：老版本 libmpv 可能没有频谱属性，那时保持默认即可。
    unawaited(
      _player.setSpectrum(const mpv.SpectrumSettings()).catchError((_) {}),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final subscription = _subscription;
    _subscription = null;
    final controller = _controller;
    _controller = null;
    await subscription?.cancel();
    await controller?.close();
  }
}