import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import '../logging/app_log.dart';
import '../logging/ohos_hilog.dart';
import 'mpv_audio_chain.dart';
import 'playback_engine.dart';
import 'stream_utils.dart';

/// 把 `mpv_audio_kit` 的 [mpv.Player] 适配成 [PlaybackEngine]。
///
/// 这是替换 HarmonyOS 上 AVPlayer 的实现，也适用于其它所有平台——
/// `mpv_audio_kit` 是纯 FFI 包，Dart 直接 `dlopen` libmpv，不经
/// ArkTS/napi，因此鸿蒙与桌面走同一条路径。
///
/// ## 为什么锁在 0.4.x
///
/// `mpv_audio_kit` 从 0.5.0 起改用 Dart native assets 构建钩子
/// （`hook/build.dart`）去下载并打包 libmpv。鸿蒙工具链既没有 native
/// assets 支持，钩子里的 `_Target.of()` 也不认识 `ohos`，会直接抛
/// `UnsupportedError`，整个 HAP 构建失败。0.4.x 是纯
/// `DynamicLibrary.open`，把库路径交给调用方决定，正是鸿蒙需要的方式。
///
/// 代价是 0.4.x 没有 `setSourceResolver`（0.5.2）与 `setMediaSession`
/// （0.7.1）。这两项在 Koyze 里都不是必需：播放地址由 Dart 侧解析后
/// 提交，媒体会话仍由 `audio_service` 的 `BaseAudioHandler` 发布。
///
/// ## 与 `just_audio` 的语义差异
///
/// 1. **`processingState` 是推导出来的**。mpv 只报告「有没有装载、在不
///    在缓冲、出不出声」，没有 `just_audio` 那套三态。这里沿用
///    `mpv_audio_kit` 自己的推导顺序（见 `deriveMpvPlaybackState`），
///    保证与上游文档一致。
/// 2. **`Media` 没有 `start` 参数**。恢复播放进度要在 `open()` 之后单独
///    `seek()`，所以 [setAudioSource] 里多一次往返。
/// 3. **`setPitch` 的语义不同**。`just_audio` 的 `setPitch` 是「变速之外
///    的额外变调」；mpv 的 `setPitch` 是独立的音高倍数。两者在 Koyze 的
///    用法里都是「1.0 = 不变」，所以直接透传。
class MpvEngine implements PlaybackEngine {
  MpvEngine(this._player, {this.supportsPcmTap = true});

  final bool supportsPcmTap;

  final mpv.Player _player;

  /// `af` 链的唯一写者。均衡器与跳过静音都往这里登记，由它合并后一次写入。
  ///
  /// 必须共用同一个实例：mpv 的 `af` 是整条替换的，两个写者各写各的会
  /// 互相抹掉。详见 [MpvAudioChain]。
  late final MpvAudioChain audioChain = MpvAudioChain(
    MpvPlayerAfWriter(_player),
  );

  /// 底层播放器。诊断页与媒体会话设置需要。
  mpv.Player get rawPlayer => _player;

  @override
  bool get playing => _player.state.playing;

  /// 由 mpv 的几个原始标志推出 `just_audio` 式的处理状态。
  ///
  /// 顺序照抄 `mpv_audio_kit` 的 `deriveMpvPlaybackState`：
  /// completed → pausedForCache → buffering → playing → 时长是否已知。
  /// 这样即使上游换了实现，两边的语义也不会分叉。
  ///
  /// 已知偏差：直播流时长为零，会被判成 [EngineProcessingState.idle]。
  /// 上游也是这个行为，不在这里单独修正——修正反而会让两边不一致。
  @override
  EngineProcessingState get processingState {
    final state = _player.state;
    // eofReached can still belong to the previous file after buffering ends.
    // Only the backend's completion flag represents a completion transition.
    if (state.completed) {
      return EngineProcessingState.completed;
    }
    if (state.pausedForCache) return EngineProcessingState.buffering;
    // mpv 的 `buffering` 指「打开文件」阶段，不是播放中的网络卡顿。
    if (state.buffering) return EngineProcessingState.loading;
    if (state.playing) return EngineProcessingState.ready;
    if (state.duration == Duration.zero) return EngineProcessingState.idle;
    return EngineProcessingState.ready;
  }

  @override
  Duration get position => _player.state.position;

  @override
  Duration? get duration {
    final value = _player.state.duration;
    // mpv 用 Duration.zero 表示「未知」（直播流、尚未解析），
    // 对齐到 just_audio 的 null 语义。
    return value <= Duration.zero ? null : value;
  }

  @override
  Duration get bufferedPosition => _player.state.buffer;

  @override
  double get speed => _player.state.rate;

  @override
  bool get shuffleModeEnabled => _player.state.shuffle;

  /// mpv 没有与 `playbackEventStream` 等价的全量事件流。
  ///
  /// 用位置流代替：位置每帧都在变，足以驱动 handler 的「重新广播状态」。
  /// 位置流在暂停时不动，所以再并入 playing 与 buffering 两条流，保证
  /// 暂停/恢复也会触发广播。
  ///
  /// 外面套一层 [_eventWindow] 节流：mpv 的 `time-pos` 由事件 isolate
  /// 按 33ms 窗口节流（约 30Hz），而 handler 每收到一次事件就要重新发布
  /// 一遍 `playbackState`。`just_audio` 的 `playbackEventStream` 是 200ms
  /// 一档（5Hz），不节流会多出 6 倍的 UI 重建——鸿蒙上这正是要避免的。
  @override
  Stream<void> get eventStream => _eventStream ??= throttleStream<void>(
    mergeStreams<void>(<Stream<void>>[
      _player.stream.position.map<void>((_) {}),
      _player.stream.playing.map<void>((_) {}),
      _player.stream.buffering.map<void>((_) {}),
      _player.stream.completed.map<void>((_) {}),
    ]),
    _eventWindow,
  );

  Stream<void>? _eventStream;

  /// 与 `just_audio` 的 `playbackEventStream` 对齐的节流窗口。
  static const Duration _eventWindow = Duration(milliseconds: 200);

  /// 处理状态变化流。
  ///
  /// mpv 0.4.x 没有现成的聚合状态流，这里把四条原始流并起来，每次事件
  /// 重新推导一次当前状态。`pausedForCache` 没有对应的流，但它变化时
  /// 播放器一定会暂停，`playing` 的事件会顺带把它带出来。
  @override
  Stream<EngineProcessingState> get processingStateStream =>
      _processingStateStream ??= _deriveProcessingStates();

  Stream<EngineProcessingState>? _processingStateStream;

  Stream<EngineProcessingState> _deriveProcessingStates() {
    late final StreamController<EngineProcessingState> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    var last = processingState;
    controller = StreamController<EngineProcessingState>(
      onListen: () {
        controller.add(last);
        for (final entry in <(String, Stream<Object?>)>[
          ('playing', _player.stream.playing),
          ('buffering', _player.stream.buffering),
          ('completed', _player.stream.completed),
          // `eof-reached` 是「播完」最原始的信号，必须自己进触发源。
          //
          // 不能指望 `completed` 把它带出来：上游的 `completed` 是
          // `eof-reached` 与 `_isEndOfContent()` 的**与**，后者读的
          // `loop` / `playlist` 两个镜像可能还没回填完，于是这个与运算
          // 恒为假、`completed` 永不触发。此时只有 `eof-reached` 自己
          // 会动，不订阅它就等于整条完成链没有入口。
          ('eof', _player.stream.eofReached),
          ('duration', _player.stream.duration),
        ]) {
          subscriptions.add(
            entry.$2.listen((_) {
              final next = processingState;
              if (next == last) return;
              // 「播完不自动切下一首」在 handler 侧已经布满了提前返回的
              // 原因日志，但那条链只在**收到 completed 事件之后**才会开口。
              // 如果 mpv 根本没把完成信号透出来，上游一行日志都不会有，看
              // 起来就像 handler 装作没事。这里把每次状态迁移的来源流、
              // 原始生命周期字段和推导结果一起打出来，真机上僵住时能直接
              // 分辨是「mpv 没发」还是「handler 拒收」。
              //
              // 必须走 [ohosLog]：`debugPrint` 在鸿蒙 HAP 里写 stdout 没有
              // 接收方，`AppLog` 默认不采集，两者都留不下痕迹。
              final state = _player.state;
              final detail =
                  'processing $last -> $next via ${entry.$1} '
                  '(completed=${state.completed} eof=${state.eofReached} '
                  'playing=${state.playing} '
                  'loop=${state.loop} buffering=${state.buffering} '
                  'playlistIndex=${state.playlist.index} '
                  'playlistLength=${state.playlist.items.length})';
              AppLog.instance.record('audio.engine', detail);
              ohosLog('KoyzeMpv', 'autonext: $detail');
              last = next;
              controller.add(next);
            }),
          );
        }
      },
      onCancel: () {
        for (final subscription in subscriptions) {
          unawaited(subscription.cancel());
        }
        subscriptions.clear();
      },
    );
    return controller.stream;
  }

  @override
  Stream<Duration?> get durationStream => _player.stream.duration.map(
    (value) => value <= Duration.zero ? null : value,
  );

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  /// mpv 没有 dedicated 的 position discontinuity 事件。
  ///
  /// 用 `seekCompleted` 代替：它是 `MPV_EVENT_PLAYBACK_RESTART`，在 seek
  /// 完全重建后触发一次，正是「位置不连续」的语义。切歌与暂停/恢复由
  /// `playing` 的变化覆盖。
  @override
  Stream<void> get positionDiscontinuityStream => mergeStreams<void>(<Stream<void>>[
    _player.stream.seekCompleted,
    _player.stream.playing.map<void>((_) {}),
  ]);

  @override
  Future<Duration?> setAudioSource(
    EngineAudioSource source, {
    Duration initialPosition = Duration.zero,
  }) async {
    // 占位静音：mpv 没有 `SilenceAudioSource` 的对应物。
    //
    // 做法是打开 mpv 的 `audio-stream-silence`——它让输出静音但保持音频
    // 设备与播放状态活着，正好是「换源间隙不能断音频会话」需要的语义。
    // 不要在这里 `stop()`：那会拆掉 demuxer、把状态打回 idle，上层会
    // 误判成「还没装载完」。
    //
    // 真正音源装载前必须关掉它，否则连正片也会被静音。
    if (source.isSilence) {
      await _setStreamSilence(true);
      return source.durationHint ?? const Duration(days: 1);
    }
    await _setStreamSilence(false);

    await _player.open(
      mpv.Media(
        source.uri,
        httpHeaders: source.headers,
        extras: _extrasFor(source.tag),
      ),
    );

    // 0.4.x 的 Media 没有 start 参数，恢复进度只能 open 之后再 seek。
    if (initialPosition > Duration.zero) {
      await _player.seek(initialPosition);
    }

    await _waitForLoad();
    return duration;
  }

  /// `audio-stream-silence` 当前是否已经打开。
  ///
  /// 只用来避免每次换源都多一次 IPC：mpv 侧这个属性是幂等的，但每次
  /// `open` 前都设一遍会白白多两个事件往返。
  bool _streamSilence = false;

  Future<void> _setStreamSilence(bool enabled) async {
    if (_streamSilence == enabled) return;
    try {
      await _player.setAudioStreamSilence(enabled);
      _streamSilence = enabled;
    } catch (_) {
      // 老版本 libmpv 可能没有这个属性；占位静音退化成无声即可，不该
      // 因此让整个换源失败。
    }
  }

  /// 音源装载完成的信号。
  ///
  /// mpv 的 `open()` 在 demuxer 打开后即返回，不像 `just_audio` 的
  /// `setAudioSource` 会等到时长解析出来。播放层依赖「装载完成」这个
  /// 时序做 stale 判定，所以这里额外等一次状态离开 loading/idle，避免
  /// 过早宣布装载成功导致后续 seek 落在空 demuxer 上。
  ///
  /// **必须有超时**：直播流时长为零，暂停状态下 `processingState` 恒为
  /// idle，[_loadFinished] 永远不会变真——没有超时就会让
  /// `setAudioSource` 永久挂起，协调器的 load token 跟着卡死，界面停在
  /// 「加载中」。超时后照常返回，让上层按「时长未知」处理。
  Future<void> _waitForLoad() async {
    if (_loadFinished) return;
    final completer = Completer<void>();
    final subscriptions = <StreamSubscription<Object?>>[];
    void settle() {
      if (completer.isCompleted) return;
      completer.complete();
    }

    for (final source in <Stream<Object?>>[
      _player.stream.duration,
      _player.stream.playing,
      _player.stream.buffering,
    ]) {
      subscriptions.add(
        source.listen(
          (_) {
            if (_loadFinished) settle();
          },
          // 装载失败由上层通过 error 流感知，这里只负责不再等下去。
          onError: (Object _, StackTrace __) => settle(),
        ),
      );
    }
    final timer = Timer(_loadTimeout, settle);

    await completer.future;
    timer.cancel();
    // 逐个显式取消：不能靠 `firstWhere` 的隐式取消，超时路径下那个
    // future 还挂着，订阅会一路泄漏到 Player 被销毁。
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  }

  /// 装载等待上限。够慢速网络把 `duration` 读出来，又不至于让界面卡死。
  static const Duration _loadTimeout = Duration(seconds: 15);

  /// 是否已经可以认为装载完成。
  bool get _loadFinished =>
      duration != null ||
      (processingState != EngineProcessingState.loading &&
          processingState != EngineProcessingState.idle);

  /// 把 `tag`（Koyze 里是 `MediaItem`）摊平成 mpv 的 `extras`，
  /// 供系统媒体会话读取标题/艺术家/封面。
  Map<String, Object?>? _extrasFor(Object? tag) {
    if (tag == null) return null;
    // 避免在这里 import audio_service 造成分层倒置，用动态读取。
    // `MediaItem` 有 id / title / artist / album / artUri 这几个字面量字段。
    try {
      final dynamic item = tag;
      final map = <String, Object?>{};
      final id = item.id;
      if (id is String) map['id'] = id;
      final title = item.title;
      if (title is String) map['title'] = title;
      final artist = item.artist;
      if (artist is String) map['artist'] = artist;
      final album = item.album;
      if (album is String) map['album'] = album;
      final artUri = item.artUri;
      if (artUri != null) map['art'] = artUri.toString();
      return map.isEmpty ? null : map;
    } catch (_) {
      // tag 不是 MediaItem（例如测试里的自定义对象），忽略即可。
      return null;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    // mpv 的 stop() 会拆掉 demuxer 并重置播放头，之后必须重新 open 才能
    // 再播（不是 play）。Koyze 的 stop 语义正是「彻底停下、等下一次装载」，
    // 与之一致。
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    ohosLog('KoyzeSeek', 'mpv seek targetMs=${position.inMilliseconds}');
    try {
      await _player.seek(position);
      ohosLog(
        'KoyzeSeek',
        'mpv seek acknowledged positionMs=${this.position.inMilliseconds}',
      );
    } catch (_) {
      ohosLog('KoyzeSeek', 'mpv seek failed');
      rethrow;
    }
  }

  /// mpv 用 `setRate` 而不是 `setSpeed`。
  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed);

  /// mpv 的音量刻度是立方，100 为原值；这里接收 0..1 线性音量，
  /// 换算成 mpv 的百分比。立方刻度由 mpv 自己处理，不必在这里补偿。
  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0) * 100);

  @override
  Future<void> setPitch(double pitch) => _player.setPitch(pitch);

  /// 跳过静音。与 `just_audio` 的 `skipSilence` 语义不同，实现也不同：
  /// mpv 没有这个开关，走 FFmpeg 的 `silenceremove` 滤镜。
  ///
  /// 这**不是**只属于 Android 的功能——只要跑的是 mpv 引擎，Android、iOS、
  /// macOS、Windows、Linux、鸿蒙都能用，因为滤镜做在 mpv 自己的音频链里，
  /// 不依赖系统音效通道。
  ///
  /// 只裁开头：中途裁剪会让滤镜输出比解复用器短，进度条从那一刻起持续
  /// 落后，且 seek 会落到错位置。理由写在 [buildMpvSkipSilenceFilters]。
  @override
  Future<void> setSkipSilenceEnabled(bool enabled) async {
    audioChain.setSkipSilence(buildMpvSkipSilenceFilters(enabled: enabled));
    // 鸿蒙上 mpv 的诊断只能走 hilog（stdout 没有接收方）。
    ohosLog('KoyzeMpv', 'skip silence = $enabled');
  }

  @override
  Future<void> setLoopMode(EngineLoopMode mode) {
    return _player.setLoop(
      switch (mode) {
        EngineLoopMode.off => mpv.Loop.off,
        EngineLoopMode.one => mpv.Loop.file,
        EngineLoopMode.all => mpv.Loop.playlist,
      },
    );
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) =>
      _player.setShuffle(enabled);

  @override
  Future<void> dispose() async {
    await audioChain.dispose();
    await _player.dispose();
  }
}
