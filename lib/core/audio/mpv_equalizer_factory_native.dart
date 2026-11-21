import 'equalizer_bridge.dart';
import 'mpv_engine.dart';
import 'mpv_equalizer_bridge.dart';
import 'playback_engine.dart';

/// 原生侧：mpv 引擎挂它自己的 `af` 滤镜链，其余引擎走平台默认实现。
///
/// 本文件**不能**出现在 Web 的编译图里：`mpv_audio_kit` 全是 `dart:ffi`
/// 的 `external` 声明，而 dart2js 只允许 JS interop 成员是 `external`。
/// 由 `mpv_equalizer_factory.dart` 做条件导入把它挡在 Web 之外。
EqualizerBridge buildEqualizerForEngine(PlaybackEngine? engine) {
  if (engine is MpvEngine) return MpvEqualizerBridge(engine);
  return createEqualizerBridge();
}