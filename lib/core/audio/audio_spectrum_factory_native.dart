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

/// 播放页频谱条该用的 FFT 参数。
///
/// 默认参数（`SpectrumSettings()`）是给网页分析器那种大画面用的，直接
/// 套到播放页会造成一个很具体的问题：**所有柱子高度差不多**，看不出
/// 低音、中音、高音的区别。原因有三条，逐条对应下面的覆盖值：
///
/// 1. **70 dB 的动态窗口太宽**。默认 `minDb = -100` / `maxDb = -30`，
///    而流行/摇滚母带的能量基本落在 -45~-8 dB。把 70 dB 线性压进
///    0.0-1.0 之后，绝大多数频段都挤在 0.4-0.7 这同一段里，相邻柱子的
///    差距不到一格像素——看起来就是「一样高」。收到 45 dB
///    （-60 → -15）之后，同样的内容能铺满整条，层次才出得来。
/// 2. **内部平滑过强**。`attackSmoothing = 0.5` / `releaseSmoothing = 0.1`
///    是给「没有外部补间」的消费者准备的；播放页的 `PlayerSpectrumStrip`
///    自己还要按帧做一次指数逼近，两层平滑叠在一起，瞬态（鼓点、拨弦）
///    的差异被抹平。这里把内部平滑降到很轻，把「怎么动」的决策权交给
///    UI 层一处。
/// 3. **64 段在窄条上过密**。条宽约 300dp 时每柱只有 4-5px，相邻频段
///    挤在一起，视觉上分不出边界。32 段给每柱约 9dp，既保留了对数分频
///    的音高语义，又能让每根柱子被眼睛单独看见——「看得出音调不同」
///    首先得「看得出这是不同的柱子」。
///
/// `fftSize` 保持 2048：约 23 Hz 的频率分辨率足以分开底鼓与 sub-bass，
/// 而 2048 点在 48 kHz 下只跨 42.7ms，仍在 A/V 同步的可接受范围内。
/// `overlapFactor` 保持 4（75% 重叠），跨帧连续性靠它，不靠平滑。
const mpv.SpectrumSettings kSpectrumSettings = mpv.SpectrumSettings(
  fftSize: 2048,
  bandCount: 32,
  bandLowHz: 30,
  bandHighHz: 16000,
  emitInterval: Duration(milliseconds: 33),
  // 内部只做极轻的防抖，避免单个异常帧造成闪烁；真正的攻击/衰减曲线
  // 在 `PlayerSpectrumStrip` 里按帧率无关的方式统一处理。
  attackSmoothing: 0.85,
  releaseSmoothing: 0.35,
  minDb: -60,
  maxDb: -15,
  overlapFactor: 4,
);

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

  void _configure() {
    if (_configured) return;
    _configured = true;
    // 失败不抛：老版本 libmpv 可能没有频谱属性，那时保持默认即可。
    unawaited(
      _player.setSpectrum(kSpectrumSettings).catchError((_) {}),
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