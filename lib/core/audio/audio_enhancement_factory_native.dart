import 'audio_enhancement.dart';
import 'mpv_audio_chain.dart';
import 'mpv_engine.dart';
import 'playback_engine.dart';

/// 原生侧的工厂。
///
/// 只有引擎真的是 mpv 时才有 `af` 链可写；just_audio 回退路径上这些
/// 增强项全部不可用（它没有等价的音效通道），返回空实现让界面把开关
/// 置灰，而不是让用户拨了没反应。
AudioEnhancementSink buildAudioEnhancementSink(PlaybackEngine? engine) {
  if (engine is MpvEngine) return MpvAudioEnhancementSink(engine);
  return const NoopAudioEnhancementSink();
}

/// 把增强项写进 mpv 的 `af` 链。
///
/// 不直接写 `af`：那条属性由 [MpvAudioChain] 独占，均衡器和跳过静音也在
/// 里面登记。这里只负责把设置翻译成滤镜条目，交给链路合并。
class MpvAudioEnhancementSink implements AudioEnhancementSink {
  MpvAudioEnhancementSink(this._engine);

  final MpvEngine _engine;

  /// 上一次施加的设置。`af` 写入是整条替换，重复写同样的内容会让 mpv
  /// 重建滤镜链，表现为播放中出现一次极短的断续。
  AudioEnhancementSettings? _applied;

  @override
  bool get isSupported => true;

  @override
  void apply(AudioEnhancementSettings settings) {
    if (_applied == settings) return;
    _applied = settings;
    final chain = _engine.audioChain;
    chain.setCrossfeed(
      buildMpvCrossfeedFilters(
        enabled: settings.crossfeedEnabled,
        strength: settings.crossfeedStrength,
      ),
    );
    chain.setLoudness(
      buildMpvLoudnessFilters(enabled: settings.loudnessEnabled),
    );
    chain.setLimiter(
      buildMpvLimiterFilters(enabled: settings.limiterEnabled),
    );
  }
}
