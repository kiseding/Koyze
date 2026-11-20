import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'playback_engine.dart';

/// 把 `just_audio` 的 [AudioPlayer] 适配成 [PlaybackEngine]。
///
/// 这是默认引擎，也是所有现存平台的引擎。适配层刻意保持「薄」：
/// 每个方法都是对 [AudioPlayer] 的直接转发，不加缓存、不加状态机、
/// 不在 Dart 侧推导任何内容。理由是下方的 455 个测试全部针对
/// `just_audio` 的具体行为编写，任何额外的中间层都会改变时序。
///
/// 唯一有实际逻辑的是音源翻译（[EngineAudioSource] → `AudioSource`）：
/// 原来这段逻辑长在 `audio_handler.dart` 里，搬到适配器后 handler 就
/// 不再需要认识 `just_audio` 的 `AudioSource` 家族。
class JustAudioEngine implements PlaybackEngine {
  JustAudioEngine(this._player);

  final AudioPlayer _player;

  /// 底层播放器。`playerStream` 的消费方仍需要具体类型，见
  /// [LxAudioHandler.playerStream] 的注释。
  AudioPlayer get rawPlayer => _player;

  @override
  bool get playing => _player.playing;

  @override
  EngineProcessingState get processingState =>
      _mapProcessingState(_player.processingState);

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Duration get bufferedPosition => _player.bufferedPosition;

  @override
  double get speed => _player.speed;

  @override
  bool get shuffleModeEnabled => _player.shuffleModeEnabled;

  /// 把 `playbackEventStream` 摊平成「状态可能变了」的信号。
  ///
  /// 消费方只用它触发广播，不解析 payload，所以这里丢掉事件内容，
  /// 顺便让抽象层不必暴露 `PlaybackEvent` 类型。
  @override
  Stream<void> get eventStream =>
      _player.playbackEventStream.map<void>((_) {});

  @override
  Stream<EngineProcessingState> get processingStateStream =>
      _player.processingStateStream.map(_mapProcessingState);

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<void> get positionDiscontinuityStream =>
      _player.positionDiscontinuityStream.map<void>((_) {});

  @override
  Future<Duration?> setAudioSource(
    EngineAudioSource source, {
    Duration initialPosition = Duration.zero,
  }) {
    return _player.setAudioSource(
      toAudioSource(source),
      initialPosition: initialPosition,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setPitch(double pitch) => _player.setPitch(pitch);

  @override
  Future<void> setSkipSilenceEnabled(bool enabled) =>
      _player.setSkipSilenceEnabled(enabled);

  @override
  Future<void> setLoopMode(EngineLoopMode mode) =>
      _player.setLoopMode(_toLoopMode(mode));

  @override
  Future<void> setShuffleModeEnabled(bool enabled) =>
      _player.setShuffleModeEnabled(enabled);

  @override
  Future<void> dispose() => _player.dispose();

  static EngineProcessingState _mapProcessingState(ProcessingState state) {
    return switch (state) {
      ProcessingState.idle => EngineProcessingState.idle,
      ProcessingState.loading => EngineProcessingState.loading,
      ProcessingState.buffering => EngineProcessingState.buffering,
      ProcessingState.ready => EngineProcessingState.ready,
      ProcessingState.completed => EngineProcessingState.completed,
    };
  }

  static LoopMode _toLoopMode(EngineLoopMode mode) {
    return switch (mode) {
      EngineLoopMode.off => LoopMode.off,
      EngineLoopMode.one => LoopMode.one,
      EngineLoopMode.all => LoopMode.all,
    };
  }

  /// 把与引擎无关的音源描述翻译回 `just_audio` 的 `AudioSource`。
  ///
  /// 优先原样返回 [EngineAudioSource.nativeSource]：那是调用方用
  /// `audioSourceFor()` 按平台挑好的具体音源（`ProgressiveAudioSource` /
  /// `SilenceAudioSource` / `LocalFileStreamAudioSource`），带着
  /// Darwin 精确时长选项等平台细节。转发它可以让重构前后的原生行为
  /// 完全一致，也让现有测试里 `loadedSource as ProgressiveAudioSource`
  /// 这类断言继续成立。
  ///
  /// 只有调用方没提供具体音源时才回退到按字段构造函数，保证接口在
  /// 其它调用路径上仍然自洽。
  static AudioSource toAudioSource(EngineAudioSource source) {
    final native = source.nativeSource;
    if (native is AudioSource) return native;
    if (source.isSilence) {
      return SilenceAudioSource(
        duration: source.durationHint ?? const Duration(days: 1),
        tag: source.tag,
      );
    }
    return AudioSource.uri(
      Uri.parse(source.uri),
      headers: source.headers,
      tag: source.tag,
    );
  }
}