import 'dart:async';
import 'dart:math' as math;

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
  if (engine is MpvEngine && engine.supportsPcmTap) {
    return MpvAudioSpectrumSource(engine.rawPlayer);
  }
  return const NoopAudioSpectrumSource();
}

/// 播放页频谱条该用的 FFT 参数。
///
/// 2048 点 FFT 在 48 kHz 下约 43 ms。保留 32 个对数频段，但提早到
/// 14 kHz 收尾，减少空气频段的占比。较低的采集底限保留微弱的泛音，
/// 最终显示范围由 [mapPlayerSpectrumBands] 按频段决定。
const mpv.SpectrumSettings kSpectrumSettings = mpv.SpectrumSettings(
  fftSize: 2048,
  bandCount: 32,
  bandLowHz: 30,
  bandHighHz: 14000,
  emitInterval: Duration(milliseconds: 25),
  // The strip shapes the unsmoothed bins once, after frequency weighting.
  attackSmoothing: 1,
  releaseSmoothing: 1,
  minDb: -80,
  maxDb: -10,
  overlapFactor: 4,
);

/// Reaggregate real FFT bins for the display. An average alone dilutes a
/// piano overtone across the many bins in a wide upper band. Blend the mean
/// with the strongest two bins and lower the visual floor towards the treble.
/// Nothing is borrowed from other bands, so absent frequencies stay quiet.
List<double> mapPlayerSpectrumBands(mpv.FftFrame frame) {
  final bins = frame.bins;
  final count = frame.bands.length;
  final values = List<double>.filled(count, 0, growable: false);
  if (bins.isEmpty ||
      count == 0 ||
      frame.sampleRate <= 0 ||
      frame.bandLowHz <= 0 ||
      frame.bandHighHz <= frame.bandLowHz) {
    return values;
  }
  final binHz = frame.sampleRate / (2 * bins.length);
  final ratio = math.pow(frame.bandHighHz / frame.bandLowHz, 1 / count);
  var lowHz = frame.bandLowHz;
  for (var i = 0; i < count; i++) {
    final highHz = lowHz * ratio;
    final start = (lowHz / binHz).floor().clamp(1, bins.length);
    final end = (highHz / binHz).ceil().clamp(start, bins.length);
    lowHz = highHz;
    if (start == end) continue;
    var sum = 0.0;
    var strongest = 0.0;
    var second = 0.0;
    for (var j = start; j < end; j++) {
      final raw = bins[j];
      final value = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;
      sum += value;
      if (value > strongest) {
        second = strongest;
        strongest = value;
      } else if (value > second) {
        second = value;
      }
    }
    final mean = sum / (end - start);
    final crest = end - start == 1 ? strongest : (strongest + second) / 2;
    final level = crest * 0.94 + mean * 0.06;
    final treble = ((i / math.max(1, count - 1) - 0.45) / 0.55).clamp(0.0, 1.0);
    final floorDb = -52 - 22 * treble;
    final db =
        kSpectrumSettings.minDb +
        level * (kSpectrumSettings.maxDb - kSpectrumSettings.minDb);
    values[i] = ((db - floorDb) / (-12 - floorDb)).clamp(0.0, 1.0);
  }
  return values;
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
    final controller = StreamController<SpectrumFrame>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    _controller = controller;
    return controller.stream;
  }

  void _start() {
    final controller = _controller;
    if (_disposed || controller == null) return;
    _configure();
    _subscription = _player.stream.fft.listen(
      (frame) {
        controller.add(
          SpectrumFrame(
            bands: mapPlayerSpectrumBands(frame),
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
  }

  void _stop() {
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
  }

  void _configure() {
    if (_configured) return;
    _configured = true;
    // 失败不抛：老版本 libmpv 可能没有频谱属性，那时保持默认即可。
    unawaited(_player.setSpectrum(kSpectrumSettings).catchError((_) {}));
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
