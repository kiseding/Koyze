import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../logging/app_log.dart';

/// 均衡器的频段布局：由播放器实际暴露的参数决定，不同设备段数不同
/// （Android 上常见 5 段，也存在 10 段实现），因此界面不能假设固定段数。
@immutable
class EqualizerBandLayout {
  const EqualizerBandLayout({
    required this.minDecibels,
    required this.maxDecibels,
    required this.centerFrequencies,
  });

  /// 设备允许的最小增益（通常为负值）。
  final double minDecibels;

  /// 设备允许的最大增益。
  final double maxDecibels;

  /// 各频段的中心频率（Hz），按设备频段顺序排列。
  final List<double> centerFrequencies;

  int get bandCount => centerFrequencies.length;

  double clampGain(double gain) => gain.clamp(minDecibels, maxDecibels);

  @override
  bool operator ==(Object other) =>
      other is EqualizerBandLayout &&
      other.minDecibels == minDecibels &&
      other.maxDecibels == maxDecibels &&
      listEquals(other.centerFrequencies, centerFrequencies);

  @override
  int get hashCode =>
      Object.hash(minDecibels, maxDecibels, Object.hashAll(centerFrequencies));

  @override
  String toString() =>
      'EqualizerBandLayout(${centerFrequencies.length} bands, '
      '$minDecibels..$maxDecibels dB)';
}

/// AutoEQ 参数均衡器里的一个 biquad。
///
/// 和 [EqualizerBandLayout] 的区别是「精度」：频段布局只能表达固定几个
/// 中心频率上的增益，而 AutoEQ 发布的曲线是若干个任意频率、任意 Q 值的
/// 滤波器。以前把它降采样到 5 个固定频段，Q 值信息全丢，窄带修正（比如
/// 3.2 kHz 的齿音峰）几乎无法还原。mpv 的 `af` 链支持任意中心频率，
/// 所以这里保留原始参数，逐个下发。
@immutable
class AutoEqBiquad {
  const AutoEqBiquad({
    required this.type,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    this.enabled = true,
  });

  /// `PK`（peaking）/ `LS`、`LSC`（低架）/ `HS`、`HSC`（高架）。
  /// 数字是老格式的 peaking。
  final String type;

  final double frequencyHz;
  final double gainDb;
  final double q;
  final bool enabled;

  bool get isLowShelf => type.toUpperCase().startsWith('LS');
  bool get isHighShelf => type.toUpperCase().startsWith('HS');

  @override
  bool operator ==(Object other) =>
      other is AutoEqBiquad &&
      other.type == type &&
      other.frequencyHz == frequencyHz &&
      other.gainDb == gainDb &&
      other.q == q &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(type, frequencyHz, gainDb, q, enabled);

  @override
  String toString() =>
      'AutoEqBiquad($type ${frequencyHz.toStringAsFixed(1)} Hz '
      '${gainDb.toStringAsFixed(1)} dB Q=${q.toStringAsFixed(2)})';
}

/// 均衡器与音频引擎之间的桥。
///
/// 关键约束：just_audio 的音效必须在 [AudioPlayer] 构造时通过
/// [AudioPipeline] 注入，无法事后追加；而 [LxAudioHandler] 在播放恢复
/// 失败时会重建播放器。所以实现方按播放器持有音效实例，并在
/// [bindPlayer] 时重新订阅与重新施加期望状态。
abstract class EqualizerBridge {
  /// 当前平台是否存在可用的均衡器实现。
  bool get isSupported;

  /// 播放器构造时注入的 Android 音效；不支持的平台返回空列表。
  List<AndroidAudioEffect> createEffects();

  /// 播放器就绪或重建后调用：重新绑定当前播放器并施加期望状态。
  void bindPlayer(AudioPlayer player);

  /// 记录期望状态，供播放器重建、首次激活后自动重新施加。
  ///
  /// [biquads] 非空表示走「参数均衡」路线（AutoEQ 原样下发），此时
  /// [gains] 不参与计算；[preampDb] 是给叠加后的峰值留的余量。
  void rememberDesired({
    required bool enabled,
    required List<double> gains,
    List<AutoEqBiquad> biquads = const <AutoEqBiquad>[],
    double preampDb = 0,
  });

  /// 当前频段布局；音效尚未激活（还没连上平台）时返回 null。
  Future<EqualizerBandLayout?> loadLayout();

  /// 立即施加状态；布局不可用时只记录期望值，等激活后自动补上。
  Future<void> apply({
    required bool enabled,
    required List<double> gains,
    List<AutoEqBiquad> biquads = const <AutoEqBiquad>[],
    double preampDb = 0,
  });

  Future<void> dispose();
}

/// 均衡器不可用的原因。
///
/// 界面需要区分这两种情况，否则会把「引擎回退」说成「平台不支持」：
///
/// * [platform]: 这个平台**从来没有**均衡器实现。iOS / macOS 的原生侧是
///   AVPlayer，没有音效通道；Windows / Linux 的 just_audio 同样没实现。
///   Web 也属于这一类。用户看到「不支持」是准确信息，没有可操作空间。
/// * [engineFallback]: 平台**本该支持**（宏蒙靠 mpv 的 `af` 链），但当前
///   跑的是 just_audio 回退路径。这通常意味着 libmpv 没加载起来，是
///   可诊断、可修的问题，不该让用户以为设备不支持。
enum EqualizerUnavailable {
  /// 平台本身没有实现。
  platform,

  /// 平台支持，但当前引擎不是 mpv。
  engineFallback,
}

/// 依平台创建均衡器桥。
///
/// 只有 Android 的 just_audio 有原生音效通道：`DarwinAudioEffect` 仅是
/// 空 mixin，iOS / macOS 侧没有任何音效注入；`just_audio_windows` 也没有。
/// 鸿蒙靠 mpv 走 `af` 链，不经过这里——见 `mpv_equalizer_factory.dart`。
EqualizerBridge createEqualizerBridge({bool? supported}) {
  final available = supported ?? (!kIsWeb && Platform.isAndroid);
  if (available) return AndroidEqualizerBridge();
  return UnsupportedEqualizerBridge(_unavailableReasonForHost());
}

/// 当前宿主在「引擎回退」时应该报哪一种不可用。
///
/// 只有鸿蒙落在 [EqualizerUnavailable.engineFallback]：它是唯一一个
/// 「平台有实现（mpv af 链）但默认引擎之外没有退路」的宿主。其它平台
/// 无论引擎是什么都没有音效通道，报 [EqualizerUnavailable.platform]。
EqualizerUnavailable _unavailableReasonForHost() {
  if (!kIsWeb && Platform.operatingSystem == 'ohos') {
    return EqualizerUnavailable.engineFallback;
  }
  return EqualizerUnavailable.platform;
}

/// 平台没有均衡器实现时的占位桥，所有操作都是空操作。
class UnsupportedEqualizerBridge implements EqualizerBridge {
  const UnsupportedEqualizerBridge([
    this.reason = EqualizerUnavailable.platform,
  ]);

  /// 不可用的原因，供界面选文案。
  final EqualizerUnavailable reason;

  @override
  bool get isSupported => false;

  @override
  List<AndroidAudioEffect> createEffects() => const [];

  @override
  void bindPlayer(AudioPlayer player) {}

  @override
  void rememberDesired({
    required bool enabled,
    required List<double> gains,
    List<AutoEqBiquad> biquads = const <AutoEqBiquad>[],
    double preampDb = 0,
  }) {}

  @override
  Future<EqualizerBandLayout?> loadLayout() async => null;

  @override
  Future<void> apply({
    required bool enabled,
    required List<double> gains,
    List<AutoEqBiquad> biquads = const <AutoEqBiquad>[],
    double preampDb = 0,
  }) async {}

  @override
  Future<void> dispose() async {}
}

/// 基于 just_audio `AndroidEqualizer` 的实现。
///
/// 所有施加上报的异常都在这里被吞掉并记日志：均衡器在个别设备上不可用
/// 时，绝不能影响正常播放。
class AndroidEqualizerBridge implements EqualizerBridge {
  AndroidEqualizerBridge({
    this.layoutTimeout = const Duration(seconds: 4),
  });

  /// 等待播放器暴露频段参数的最长时间。超时不算失败——播放器还没加载过
  /// 音频源时平台尚未连接，参数自然拿不到，等开始播放后会自己补上。
  final Duration layoutTimeout;

  AndroidEqualizer? _effect;
  StreamSubscription<PlayerState>? _stateSubscription;
  EqualizerBandLayout? _layout;
  bool _desiredEnabled = false;
  List<double> _desiredGains = const [];

  /// 串行队列：施加操作不并发、不丢弃，用户连续拖动滑块也不会错序。
  Future<void> _queue = Future<void>.value();
  Future<void>? _disposed;

  @override
  bool get isSupported => true;

  @override
  List<AndroidAudioEffect> createEffects() {
    final effect = AndroidEqualizer();
    _effect = effect;
    // 新播放器还没连上平台，之前的布局与参数都失效了。
    _layout = null;
    return <AndroidAudioEffect>[effect];
  }

  @override
  void bindPlayer(AudioPlayer player) {
    _stateSubscription?.cancel();
    _layout = null;
    _stateSubscription = player.playerStateStream.listen((state) {
      // 平台连接（首次载入音频源）后音效参数才可用。processingState 离开
      // idle 说明已经连上，此时补一次施加；布局已就绪则不再重复。
      if (_layout == null && state.processingState != ProcessingState.idle) {
        unawaited(_enqueue());
      }
    });
    unawaited(_enqueue());
  }

  @override
  void rememberDesired({
    required bool enabled,
    required List<double> gains,
    List<AutoEqBiquad> biquads = const <AutoEqBiquad>[],
    double preampDb = 0,
  }) {
    _desiredEnabled = enabled;
    _desiredGains = List<double>.of(gains);
    // 系统音效通道只有固定频段，无法表达任意 Q 值。AutoEQ 的曲线在
    // 上层已经被采样成频段增益，这里直接用那份结果——精度差一些，但
    // 这是 just_audio 回退路径的固有限制，不是这里能补的。
  }

  @override
  Future<EqualizerBandLayout?> loadLayout() async {
    if (_layout != null) return _layout;
    await _enqueue();
    return _layout;
  }

  @override
  Future<void> apply({
    required bool enabled,
    required List<double> gains,
    List<AutoEqBiquad> biquads = const <AutoEqBiquad>[],
    double preampDb = 0,
  }) {
    rememberDesired(
      enabled: enabled,
      gains: gains,
      biquads: biquads,
      preampDb: preampDb,
    );
    // 不等待结果：播放器还没激活时这里会一直等到超时，用户操作不该被拖住。
    // 布局不可用时期望值已经记下，等激活后由 bindPlayer / 播放状态变化补上。
    unawaited(_enqueue());
    return Future<void>.value();
  }

  Future<void> _enqueue() {
    if (_disposed != null) return Future<void>.value();
    final next = _queue.then((_) => _applyDesired()).catchError((_) {});
    _queue = next;
    return next;
  }

  Future<void> _applyDesired() async {
    if (_disposed != null) return;
    final effect = _effect;
    if (effect == null) return;
    try {
      final parameters = await effect.parameters.timeout(layoutTimeout);
      if (_disposed != null) return;
      final layout = EqualizerBandLayout(
        minDecibels: parameters.minDecibels,
        maxDecibels: parameters.maxDecibels,
        centerFrequencies: <double>[
          for (final band in parameters.bands) band.centerFrequency,
        ],
      );
      _layout = layout;
      if (effect.enabled != _desiredEnabled) {
        await effect.setEnabled(_desiredEnabled);
      }
      final bands = parameters.bands;
      for (var i = 0; i < bands.length; i++) {
        // 期望增益的段数与设备不一致时（例如从别的机型同步过来），
        // 缺失的段按 0 dB 处理，不做过度假设。
        final target = layout.clampGain(
          i < _desiredGains.length ? _desiredGains[i] : 0,
        );
        if (bands[i].gain != target) {
          await bands[i].setGain(target);
        }
      }
    } on TimeoutException {
      // 播放器尚未连接平台，保持现状，等 bindPlayer / 播放状态变化后再试。
    } catch (error, stackTrace) {
      AppLog.instance.record(
        'audio.equalizer',
        'apply failed: $error',
        level: AppLogLevel.warning,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> dispose() => _disposed ??= _dispose();

  Future<void> _dispose() async {
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    // 音效由播放器原生侧随 AudioPlayer.dispose 一并释放，这里只断开引用。
    _effect = null;
    _layout = null;
  }
}
