import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:just_audio/just_audio.dart' show AndroidAudioEffect, AudioPlayer;

import '../logging/app_log.dart';
import 'equalizer_bridge.dart';
import 'mpv_engine.dart';

/// mpv 侧均衡器的频段布局。
///
/// 与 `kFallbackEqualizerLayout` 取值一致：用户已经保存的自定义曲线是
/// 按这套频段写下来的，换一套中心频率会让旧数据整体错位。改这里必须
/// 同时改那边，`mpv_equalizer_bridge_test.dart` 会盯着。
const EqualizerBandLayout kMpvEqualizerLayout = EqualizerBandLayout(
  minDecibels: -12,
  maxDecibels: 12,
  centerFrequencies: <double>[60, 230, 910, 3600, 14000],
);

/// 带宽上下限（倍频程）。
///
/// 下限 0.5 保证单个频段至少能推开半个倍频程，再窄就只剩一个能听出
/// 「啸叫」的尖峰；上限 2 保证频段之间不会过度互相渗透，否则整条曲线
/// 会被抹成一条斜坡，滑块拖起来像在调总音量。
const double kEqualizerMinBandWidthOctaves = 0.5;
const double kEqualizerMaxBandWidthOctaves = 2;

/// 单个频段的带宽（倍频程），由相邻频段的间距推算。
///
/// ffmpeg `equalizer` 的 `width_type=o` 是**滤波器半功率带宽**：给 1 就是
/// 一个倍频程。而五段布局的相邻中心频率相隔约 1.95 个倍频程（60/230/
/// 910/3600/14000），若仍按 1 倍频程施加，每个频段只覆盖到目标区间的一半
/// ——实测相邻频段中点处响应会掉回 0 dB 附近，于是「五个频段各自提升」在
/// 听感上几乎等于没开。
///
/// 这里按「覆盖到相邻频段的中点」反推：中点到中心是间距的一半，单侧要
/// 伸那么远，总宽就是整个间距。五段得到约 1.95，十段得到约 1.0。
///
/// 两端频段按最近的一段间距外推，避免出现比中间更窄的带宽。
double mpvEqualizerBandWidthOctaves(
  EqualizerBandLayout layout,
  int index,
) {
  final frequencies = layout.centerFrequencies;
  if (frequencies.length < 2) return 1;
  final center = frequencies[index.clamp(0, frequencies.length - 1)];
  if (center <= 0) return 1;

  // 两端用相邻的那一段间距，中间取与两侧间距的平均值（对数轴上）。
  double gapTo(int other) =>
      (math.log(frequencies[other] / center) / math.ln2).abs();

  final double gap;
  if (index <= 0) {
    gap = gapTo(1);
  } else if (index >= frequencies.length - 1) {
    gap = gapTo(frequencies.length - 2);
  } else {
    gap = (gapTo(index - 1) + gapTo(index + 1)) / 2;
  }
  if (!gap.isFinite || gap <= 0) return 1;
  return gap.clamp(
    kEqualizerMinBandWidthOctaves,
    kEqualizerMaxBandWidthOctaves,
  );
}

/// 把频段增益编成 ffmpeg `equalizer` 滤镜条目。
///
/// 每条对应 mpv `af` 链路里的一个滤镜；返回空列表表示「不需要挂任何
/// 滤镜」。单独抽成纯函数是为了能测：这里拼错一个冒号，用户听到的是
/// 「均衡器没反应」而不是报错，靠肉眼很难发现。
///
/// 关掉、或者所有增益都贴着 0 dB（±0.05 以内）时返回空列表——不挂滤镜
/// 可以省掉每帧五次双二阶滤波的开销，听感完全一样。
List<String> buildMpvEqualizerFilters({
  required bool enabled,
  required List<double> gains,
  EqualizerBandLayout layout = kMpvEqualizerLayout,
}) {
  if (!enabled) return const <String>[];
  final filters = <String>[];
  for (var i = 0; i < layout.bandCount; i++) {
    final raw = i < gains.length ? gains[i] : 0.0;
    if (!raw.isFinite) continue;
    final gain = layout.clampGain(raw);
    if (gain.abs() < 0.05) continue;
    // 带宽按频段疏密自动推算，见 [mpvEqualizerBandWidthOctaves]。
    final frequency = _formatNumber(layout.centerFrequencies[i]);
    final width = _formatNumber(mpvEqualizerBandWidthOctaves(layout, i));
    final value = _formatNumber(gain);
    filters.add(
      'equalizer=f=$frequency:width_type=o:width=$width:g=$value',
    );
  }
  return filters;
}

/// 兼容旧口径：把滤镜条目串成一条 `af` 字符串（用逗号分隔）。
///
/// 走 [MpvEqualizerBridge] 时用的是 [buildMpvEqualizerFilters] + 官方
/// `setAudioEffects`；这个函数只用于诊断输出与测试断言。
String buildMpvEqualizerFilter({
  required bool enabled,
  required List<double> gains,
  EqualizerBandLayout layout = kMpvEqualizerLayout,
}) =>
    buildMpvEqualizerFilters(
      enabled: enabled,
      gains: gains,
      layout: layout,
    ).join(',');

String _formatNumber(double value) {
  final text = value.toStringAsFixed(2);
  // 12.00 → 12；3.50 → 3.5；-0.00 → 0
  final trimmed = text
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return trimmed == '-0' ? '0' : trimmed;
}

/// 基于 libmpv 的 `af`（音频滤镜链）实现的均衡器。
///
/// 为什么这条路能「全平台」：均衡不做在系统音效层，而是塞进 mpv 自己的
/// 音频滤镜链。只要这个平台跑的是 mpv 引擎，`af` 就存在 —— Android、
/// 鸿蒙、Windows、macOS、Linux 走的是同一份实现，不再受「just_audio 只有
/// Android 有音效通道」的限制。
///
/// 与 [AndroidEqualizerBridge] 的差别：那边依赖播放器暴露的频段参数，
/// 播放器没连上平台时拿不到；这边布局是固定的，进页面就能画滑块。
///
/// **不自己写 `af`**：写整条链路会让同进程里的另一个写者（跳过静音）被
/// 抹掉。这里只登记自己的滤镜，由引擎侧的 [MpvAudioChain] 合并后一次写入。
class MpvEqualizerBridge implements EqualizerBridge {
  MpvEqualizerBridge(
    this._engine, {
    this.debounce = const Duration(milliseconds: 120),
  });

  final MpvEngine _engine;

  /// 合并连续拖动。滑块每帧都会回调，直接写属性会让 mpv 反复重建滤镜链。
  final Duration debounce;

  bool _desiredEnabled = false;
  List<double> _desiredGains = const <double>[];
  String? _appliedValue;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  @override
  bool get isSupported => true;

  /// mpv 的音效不是通过 just_audio 的 [AudioPipeline] 注入的，
  /// 这个方法对它没有意义。
  @override
  List<AndroidAudioEffect> createEffects() => const <AndroidAudioEffect>[];

  /// mpv 引擎没有需要重新绑定的原生播放器：滤镜跟着 mpv 实例走。
  @override
  void bindPlayer(AudioPlayer player) {}

  @override
  void rememberDesired({required bool enabled, required List<double> gains}) {
    _desiredEnabled = enabled;
    _desiredGains = List<double>.of(gains);
  }

  @override
  Future<EqualizerBandLayout?> loadLayout() async => kMpvEqualizerLayout;

  @override
  Future<void> apply({required bool enabled, required List<double> gains}) {
    rememberDesired(enabled: enabled, gains: gains);
    _schedule();
    // 与 Android 侧一致：不阻塞调用方，失败只记日志。
    return Future<void>.value();
  }

  void _schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, _enqueue);
  }

  Future<void> _enqueue() {
    if (_disposed) return Future<void>.value();
    final next = _queue.then((_) => _applyDesired()).catchError((_) {});
    _queue = next;
    return next;
  }

  Future<void> _applyDesired() async {
    if (_disposed) return;
    final filters = buildMpvEqualizerFilters(
      enabled: _desiredEnabled,
      gains: _desiredGains,
    );
    // 用滤镜链本身当签名，避免同样的状态重复写属性。
    final signature = filters.join(',');
    if (signature == _appliedValue) return;
    _appliedValue = signature;
    // 只登记，不落盘：引擎会把这条与跳过静音合并后写入 af。
    _engine.audioChain.setEqualizer(filters);
    AppLog.instance.record(
      'audio.equalizer',
      signature.isEmpty ? 'mpv eq cleared' : 'mpv eq = $signature',
    );
  }

  /// 等待当前排队的写入完成。测试用。
  @visibleForTesting
  Future<void> get settled => _queue;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
