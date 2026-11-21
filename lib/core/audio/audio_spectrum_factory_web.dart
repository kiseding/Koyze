import 'audio_spectrum.dart';
import 'playback_engine.dart';

/// Web 侧没有 mpv，也没有等价的频谱管线。
///
/// 这里刻意不 import 任何 mpv 符号：dart2js 会把 `package:mpv_audio_kit`
/// 里的 `external` 声明当成非 JS interop 成员而整条编译失败。
AudioSpectrumSource buildAudioSpectrumSource(PlaybackEngine? engine) =>
    const NoopAudioSpectrumSource();