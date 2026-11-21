import 'equalizer_bridge.dart';
import 'mpv_equalizer_factory_web.dart'
    if (dart.library.io) 'mpv_equalizer_factory_native.dart'
    as impl;
import 'playback_engine.dart';

/// 按播放引擎挑均衡器实现。
///
/// mpv 走自己的 `af` 音频滤镜链，因此均衡器在所有跑 mpv 的平台上都可用；
/// just_audio 仍然只有 Android 有原生音效通道，其余平台返回空实现。
///
/// 为什么要绕一层条件导入：[mpv_engine.dart] 与 [mpv_equalizer_bridge.dart]
/// 都依赖 `package:mpv_audio_kit`，而它里面全是 `dart:ffi` 的 `external`
/// 声明。dart2js 只允许 JS interop 成员是 `external`，一旦这些文件进入
/// Web 的编译图就会直接报 "Only JS interop members may be 'external'"。
///
/// 曾经踩过：`LxAudioHandler` 为了做 `engine is MpvEngine` 的类型判断直接
/// import 了 mpv，而 Web 入口经 `audio_handler.dart` 一路可达，于是整条
/// Web 构建挂掉。类型判断必须留在原生那一侧——这个文件与 `_native`/`_web`
/// 两个实现都不被 Web 编译，Web 侧只拿到一个恒返回普通实现的桩。
EqualizerBridge equalizerForEngine(PlaybackEngine? engine) =>
    impl.buildEqualizerForEngine(engine);