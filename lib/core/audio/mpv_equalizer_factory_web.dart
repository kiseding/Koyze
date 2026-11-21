import 'equalizer_bridge.dart';
import 'playback_engine.dart';

/// Web 侧：没有 libmpv，也不可能出现 mpv 引擎。
///
/// 与 `mpv_equalizer_factory_native.dart` 保持同一签名，由
/// `mpv_equalizer_factory.dart` 按平台条件导入。这里刻意不 import 任何
/// mpv 相关文件——`mpv_audio_kit` 的 `dart:ffi` 声明会让 dart2js 直接
/// 编译失败（"Only JS interop members may be 'external'"）。
EqualizerBridge buildEqualizerForEngine(PlaybackEngine? engine) =>
    createEqualizerBridge();