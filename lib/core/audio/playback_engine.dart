/// 播放引擎的抽象。
///
/// 存在的理由：Koyze 原来直接绑死 `just_audio` 的 [AudioPlayer]，但
/// HarmonyOS 上 AVPlayer 有缓冲与时序问题，需要换成 libmpv。如果让
/// [LxAudioHandler] 与 `PlaybackCommandCoordinator` 继续按具体类编程，
/// 换引擎就等于重写整个播放层（约 5000 行）。
///
/// 这里只抽取「播放层真正用到的那部分」——不是照搬 `just_audio` 的
/// 全量 API。方法集合由 `grep -oE "(_player|player)\.[a-zA-Z_]+"`
/// 的实际调用面决定，因此两边适配器都不必实现用不到的东西。
///
/// 刻意不依赖 `package:just_audio`：本文件被 `just_audio_engine.dart`
/// 与 `mpv_engine.dart` 共同实现，任何一侧的类型泄漏都会让另一侧无法编译。
library;

import 'dart:async';

/// 引擎的处理状态。
///
/// 与 `just_audio` 的 `ProcessingState` 一一对应，但独立声明，避免抽象层
/// 依赖具体包。`AudioProcessingState`（`audio_service` 的展示态）由
/// [LxAudioHandler] 单独映射，两者不要混用。
enum EngineProcessingState {
  /// 没有装载任何音源。
  idle,

  /// 正在装载。
  loading,

  /// 已就绪、可播放（可能在缓冲网络数据）。
  buffering,

  /// 可以播放且已缓冲足够。
  ready,

  /// 播放到结尾。
  completed,
}

/// 交给引擎的音源描述。
///
/// 这是一个**容器**而不是替代品：它把「用什么地址、带什么请求头、挂什么
/// 标签」抽出来，同时留了一个 [nativeSource] 字段承载引擎私有的音源对象。
///
/// 为什么要留 [nativeSource]：现有播放层与 455 个测试都在按
/// `just_audio` 的 `ProgressiveAudioSource` / `SilenceAudioSource`
/// 做类型判断与断言（`loadedSource as ProgressiveAudioSource`）。若强行
/// 把那些类型从接口里抹掉，代价是重写 139 处测试断言，而收益为零——
/// 它们本来就在测 `just_audio` 的行为。
///
/// 因此约定：**识别不了的引擎原样使用 [nativeSource]，识别得了的引擎
/// 读 [uri] / [headers] / [isSilence] 自己翻译**。mpv 侧走后者，
/// `just_audio` 侧走前者，两边都不必迁就对方。
class EngineAudioSource {
  const EngineAudioSource({
    required this.uri,
    this.headers,
    this.tag,
    this.durationHint,
    this.isSilence = false,
    this.nativeSource,
  });

  /// 音源地址。空字符串表示「占位静音」，见 [isSilence]。
  final String uri;

  /// 随请求发送的 HTTP 头（Referer / User-Agent 等）。
  final Map<String, String>? headers;

  /// 调用方附加的数据，引擎原样带回。
  final Object? tag;

  /// 占位静音的长度；只有 [isSilence] 为 true 时有意义。
  final Duration? durationHint;

  /// 是否为「未解析曲目」的超长静音占位。
  ///
  /// `just_audio` 用 `SilenceAudioSource` 实现；mpv 侧用静音轨近似。
  final bool isSilence;

  /// 引擎私有的音源对象，目前是 `just_audio` 的 `AudioSource`。
  ///
  /// `just_audio` 适配器直接转发它，从而保证现网行为与重构前逐字节相同；
  /// mpv 适配器忽略它，只用上面的通用字段。
  final Object? nativeSource;

  /// 把「已经是本类型」或「引擎原生音源」统一成本类型。
  ///
  /// 存在的理由：`PlaybackCommandCoordinator.commitSource` 的调用方有两类——
  /// 生产代码传 [EngineAudioSource]（同时带上 uri 与 nativeSource），
  /// 而既有测试与 `just_audio` 专用路径直接传 `AudioSource`。这里把后者
  /// 包一层，[nativeSource] 原样保留，于是 `just_audio` 侧行为不变、
  /// mpv 侧只看得到它认识的字段。
  ///
  /// 本文件不 import `just_audio`，所以这里无法对 `AudioSource` 做类型
  /// 判断，只能「不是本类型就当原生音源」。这正是想要的语义：抽象层不
  /// 需要知道具体引擎有哪些音源类。
  factory EngineAudioSource.from(Object source) {
    if (source is EngineAudioSource) return source;
    return EngineAudioSource(uri: '', nativeSource: source);
  }
}

/// 播放引擎。
///
/// 生命周期由 [LxAudioHandler] 掌管：构造 → 反复使用 → [dispose]。
/// 实现者不需要自己处理音频焦点、媒体会话或后台播放策略，那些在
/// handler 与 `audio_service` 层。
abstract class PlaybackEngine {
  /// 是否正在出声。
  ///
  /// 注意这是「实际输出」而非「用户意图」。锁屏按钮应读 handler 的
  /// desired playing，不要直接读这个。
  bool get playing;

  /// 当前处理状态。
  EngineProcessingState get processingState;

  /// 当前播放位置。
  Duration get position;

  /// 当前音源总时长；未知时为 null。
  Duration? get duration;

  /// 已缓冲到的位置。
  Duration get bufferedPosition;

  /// 播放速度倍数。
  double get speed;

  /// 随机播放是否开启。
  bool get shuffleModeEnabled;

  /// 播放状态变化的粗粒度事件流。
  ///
  /// handler 用它做「状态可能变了，重新广播一次」的触发器，不解析内容。
  Stream<void> get eventStream;

  /// 处理状态变化流，已完成时会发出 [EngineProcessingState.completed]。
  Stream<EngineProcessingState> get processingStateStream;

  /// 时长变化流。
  Stream<Duration?> get durationStream;

  /// 位置变化流。用于「等待播放进度推进」这类轮询。
  Stream<Duration> get positionStream;

  /// 位置发生不连续跳变时发出事件（seek、切歌、后台恢复）。
  ///
  /// 消费方拿它做「进度条要重新对齐」的触发器：正常播放时位置是连续的，
  /// 不连续就意味着不能信任上一帧的位置。锁屏同步与桌面媒体会话都依赖
  /// 这个信号，缺了它进度条会在 seek 后卡住。
  ///
  /// 不携带具体位置：消费方读 [position] 即可，避免两处数据不一致。
  Stream<void> get positionDiscontinuityStream;

  /// 装载音源。[initialPosition] 用于恢复播放进度。
  Future<Duration?> setAudioSource(
    EngineAudioSource source, {
    Duration initialPosition = Duration.zero,
  });

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  /// 设置播放速度。
  Future<void> setSpeed(double speed);

  /// 设置音量（0.0–1.0 线性）。
  Future<void> setVolume(double volume);

  /// 设置音高倍数。不支持音高校正的引擎可以退化为无操作。
  Future<void> setPitch(double pitch);

  /// 开启/关闭「跳过静音」。不支持的引擎退化为无操作。
  Future<void> setSkipSilenceEnabled(bool enabled);

  Future<void> setLoopMode(EngineLoopMode mode);

  Future<void> setShuffleModeEnabled(bool enabled);

  Future<void> dispose();
}

/// 循环模式。对应 `just_audio` 的 `LoopMode`。
enum EngineLoopMode { off, one, all }