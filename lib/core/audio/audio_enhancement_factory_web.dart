import 'audio_enhancement.dart';
import 'playback_engine.dart';

/// Web 侧的工厂。
///
/// 浏览器上跑的是 Web Audio，没有 mpv 的 `af` 链，这些增强项都不可用。
/// 这个文件**不能**出现任何 mpv 符号：它会被 dart2js 编译，而
/// `mpv_audio_kit` 的 FFI `external` 声明会让编译直接失败。
AudioEnhancementSink buildAudioEnhancementSink(PlaybackEngine? engine) =>
    const NoopAudioEnhancementSink();
