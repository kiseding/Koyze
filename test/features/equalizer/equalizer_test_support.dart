import 'package:just_audio/just_audio.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';

/// Android 上最常见的 5 段布局。
const List<double> fiveBandFrequencies = <double>[60, 230, 910, 3600, 14000];

/// 部分设备暴露的 10 段布局。
const List<double> tenBandFrequencies = <double>[
  32,
  64,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

const EqualizerBandLayout fiveBandLayout = EqualizerBandLayout(
  minDecibels: -15,
  maxDecibels: 15,
  centerFrequencies: fiveBandFrequencies,
);

const EqualizerBandLayout tenBandLayout = EqualizerBandLayout(
  minDecibels: -15,
  maxDecibels: 15,
  centerFrequencies: tenBandFrequencies,
);

/// 记录施加内容的假桥，用来断言上层真的把状态推给了音频层。
class FakeEqualizerBridge implements EqualizerBridge {
  FakeEqualizerBridge({this.supported = true, this.layout});

  final bool supported;
  EqualizerBandLayout? layout;

  final List<({bool enabled, List<double> gains})> applies =
      <({bool enabled, List<double> gains})>[];
  ({bool enabled, List<double> gains})? desired;

  @override
  bool get isSupported => supported;

  @override
  List<AndroidAudioEffect> createEffects() => const <AndroidAudioEffect>[];

  @override
  void bindPlayer(AudioPlayer player) {}

  @override
  void rememberDesired({required bool enabled, required List<double> gains}) {
    desired = (enabled: enabled, gains: List<double>.of(gains));
  }

  @override
  Future<EqualizerBandLayout?> loadLayout() async => layout;

  @override
  Future<void> apply({
    required bool enabled,
    required List<double> gains,
  }) async {
    rememberDesired(enabled: enabled, gains: gains);
    applies.add(desired!);
  }

  @override
  Future<void> dispose() async {}
}
