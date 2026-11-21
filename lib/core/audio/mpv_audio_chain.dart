import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import '../logging/app_log.dart';

/// 写 `af` 链路的最小接口。
///
/// 抽出这一层是为了能测：`mpv.Player` 需要真的 libmpv 才能构造，单测里
/// 拿不到它，而链路拼装与降级逻辑恰恰是最容易悄悄写错的部分。
abstract class MpvAfWriter {
  Future<void> writeAf(List<String> filters);
}

/// 真实实现：把整条链路一次性写进 mpv。
///
/// 不能直接写 `af` 属性——`mpv_audio_kit` 把这条属性托管给了
/// `AudioEffects`，直写会被拒绝（"Property `af` is owned by the typed
/// AudioEffects bundle"）。`custom` 里的每条字符串就是 af 链里的一环。
class MpvPlayerAfWriter implements MpvAfWriter {
  MpvPlayerAfWriter(this._player);

  final mpv.Player _player;

  @override
  Future<void> writeAf(List<String> filters) =>
      _player.setAudioEffects(mpv.AudioEffects(custom: filters));
}

/// 把各段滤镜拼成最终链路。
///
/// **顺序有讲究**：
/// * 跳过静音在最前——它要判断「这一段是不是空白」，必须在均衡器抬过噪声
///   基底之前看到原始信号，否则 −50 dB 的静音被 +12 dB 的低频增益抬到
///   −38 dB，就再也判不成静音了。
/// * 均衡器（含 Preamp）随后：Preamp 是给叠加后的峰值留的余量，必须在
///   滤波器之前，否则等于「先削波再衰减」。
/// * 交叉馈送排在音色之后：它做的是声道间混音，先定好音色再决定混多少，
///   顺序反了会让低频被串到对侧后再被 EQ 抬一次。
/// * 响度归一倒数第二：它要看到所有音色处理之后的电平。
/// * 限幅器必须最后：它看的是最终输出电平，放中间就管不到后面的增益。
List<String> composeMpvFilterChain({
  required List<String> skipSilence,
  required List<String> equalizer,
  List<String> crossfeed = const <String>[],
  List<String> loudness = const <String>[],
  List<String> limiter = const <String>[],
  bool skipSilenceDegraded = false,
}) {
  final chain = <String>[];
  if (!skipSilenceDegraded) chain.addAll(skipSilence);
  chain.addAll(equalizer);
  chain.addAll(crossfeed);
  chain.addAll(loudness);
  chain.addAll(limiter);
  return chain;
}

/// 跳过静音对应的 silenceremove 参数。
///
/// 只处理**开头**的空白（`start_periods=1`，`stop_periods` 留 0）。
///
/// 曲子中间的静音不在这里处理，是刻意取舍：`silenceremove` 是实时滤镜，
/// 一旦在中途丢掉几秒，滤镜输出的时间轴就比解复用器短，进度条会从此
/// 落后于真实播放位置，seek 也会落在错的地方。开头空白没有这个累积
/// 问题，收益（专辑前奏留白、隐藏轨前的长静音）却占了绝大多数。
///
/// `start_silence` 保留 100 ms，避免把第一个音的起振削掉——直接贴到
/// 波形前沿会听成「啪」的一下。
///
/// 阈值 0.00316 ≈ −50 dBFS：CD 转录的底噪通常在 −60 到 −70 dB，不会被
/// 误判成有声；而 24bit 母带的极低电平段落也不会被当成静音切掉。
List<String> buildMpvSkipSilenceFilters({bool enabled = true}) {
  if (!enabled) return const <String>[];
  return const <String>[
    'silenceremove=start_periods=1'
    ':start_silence=0.1'
    ':start_threshold=0.00316'
    ':detection=rms',
  ];
}

/// 交叉馈送：缓解耳机听硬声像录音时的「头中效应」。
///
/// 早期立体声录音常把乐器整个塞在左或右声道，用耳机听就是「左边一个
/// 人在演奏，右边空的」。音箱上不会这样，因为左耳也能听到右箱的声音。
/// `crossfeed` 就是模拟这件事：把对侧声道按一个短延迟、低通之后混一点
/// 过来。
///
/// 参数取 0.35 的强度、0.5 的范围——比 foobar2000 的默认值略保守。
/// 强度再高会让声场明显变窄，反而不如原声。
///
/// 只对耳机有意义，外放时开着等于白损失分离度，所以做成开关而不是默认开。
List<String> buildMpvCrossfeedFilters({
  required bool enabled,
  double strength = 0.35,
}) {
  if (!enabled) return const <String>[];
  final value = strength.isFinite ? strength.clamp(0.0, 1.0) : 0.35;
  return <String>[
    'crossfeed=strength=${_formatFilterNumber(value)}:range=0.5:slope=0.5',
  ];
}

/// 响度均衡：把不同录音之间忽大忽小的音量拉平。
///
/// 用 `dynaudnorm` 而不是 `loudnorm`：后者是双 pass 设计，实时单 pass
/// 时会在开播三秒内做一次测量，seek 之后又要重新测，表现为「跳一下
/// 音量」。`dynaudnorm` 是纯流式的，代价是会轻微压动态。
///
/// 参数刻意放缓：`f=1500` 的 1.5 秒窗口 + `g=101` 的高斯平滑，让它
/// 只跟住「这一段比上一段响」这种量级的变化，而不是逐字压。`m=3` 把
/// 最大提升限制在 3 倍（约 +9.5 dB），避免把底噪一起抬起来。
///
/// 注意它和 ReplayGain 是两套机制：ReplayGain 按标签给一个固定的曲目
/// 增益，不改变动态；这里是实时的。同时开不会互相破坏，但会叠加补偿，
/// 所以设置页把两者放在一起说明。
List<String> buildMpvLoudnessFilters({required bool enabled}) {
  if (!enabled) return const <String>[];
  return const <String>[
    'dynaudnorm=f=1500:g=101:p=0.95:m=3',
  ];
}

/// 链尾限幅：把超过天花板的峰值压回来，而不是让它们硬削。
///
/// 为什么需要：均衡器把某个频段推 +12 dB 时，原本接近 0 dBFS 的信号
/// 会溢出。以前靠 `normalizeEqualizerGains` 把曲线峰值夹住来预防，那是
/// 静态的、按最坏情况估计的；挂一个限幅器之后，实际没溢出的素材完全
/// 不受影响，只有真的顶到天花板的那几个采样被压。
///
/// `level=0` 关掉自动电平补偿——那是给「限幅后整体变小」的素材补音量
/// 用的，在音乐播放里会让安静段落被抬起来，听感反而更差。
List<String> buildMpvLimiterFilters({
  required bool enabled,
  double ceiling = 0.95,
}) {
  if (!enabled) return const <String>[];
  final limit = ceiling.isFinite ? ceiling.clamp(0.5, 1.0) : 0.95;
  return <String>[
    'alimiter=limit=${_formatFilterNumber(limit)}:level=0:attack=5:release=50',
  ];
}

String _formatFilterNumber(double value) {
  final text = value.toStringAsFixed(3);
  return text
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// `af` 链的唯一写者。
///
/// 为什么要「唯一」：mpv 只有一条 `af`，而 `setAudioEffects` 是**整条替换**
/// 的。均衡器和跳过静音各写各的时，后写的那个会把前一个抹掉——表现出来
/// 就是「开了跳过静音，均衡器就失效」，或者反过来。所以两者都只登记自己
/// 那几段，由这里合并成一条链路再写下去。
class MpvAudioChain {
  MpvAudioChain(
    this._writer, {
    this.debounce = const Duration(milliseconds: 120),
  });

  final MpvAfWriter _writer;

  /// 合并连续拖动。滑块每帧都会回调，直接写属性会让 mpv 反复重建滤镜链。
  final Duration debounce;

  List<String> _skipSilence = const <String>[];
  List<String> _equalizer = const <String>[];
  List<String> _crossfeed = const <String>[];
  List<String> _loudness = const <String>[];
  List<String> _limiter = const <String>[];

  /// silenceremove 写失败后永久降级：宁可没有跳过静音，也不能让它连带
  /// 把均衡器一起拖死。只在第一次失败时记一条日志，不刷屏。
  bool _skipSilenceDegraded = false;

  /// 其它可选环节的降级标记。
  ///
  /// 每个新滤镜都是一次「这份 libmpv 到底编没编它」的赌博：`crossfeed`
  /// 依赖 libavfilter 的编译选项，`dynaudnorm` 和 `alimiter` 同理。任意
  /// 一个不被支持，整条 `af` 写入就会失败——而失败的表现是「什么效果都
  /// 没有」，用户只会觉得均衡器坏了。所以按「可牺牲程度」逐个降级，
  /// 保住用户真正调过的那条曲线。
  bool _crossfeedDegraded = false;
  bool _loudnessDegraded = false;
  bool _limiterDegraded = false;

  String? _appliedSignature;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  /// 合并窗口内还有一次待执行的写入时，用它通知 [settled]。
  ///
  /// 没有它的话，`setEqualizer` → `await settled` 会立刻返回旧队列的结果，
  /// 而真正的写入还在 120ms 定时器里没开始——测试会看到「上一次的状态」，
  /// 排查起来像是链路没合并。
  Completer<void>? _pendingSettle;

  /// 当前生效的链路（已降级的不含被放弃的环节）。诊断与测试用。
  List<String> get filters => composeMpvFilterChain(
    skipSilence: _skipSilence,
    equalizer: _equalizer,
    crossfeed: _crossfeedDegraded ? const <String>[] : _crossfeed,
    loudness: _loudnessDegraded ? const <String>[] : _loudness,
    limiter: _limiterDegraded ? const <String>[] : _limiter,
    skipSilenceDegraded: _skipSilenceDegraded,
  );

  bool get skipSilenceDegraded => _skipSilenceDegraded;

  /// 登记跳过静音。传空列表表示关闭。
  void setSkipSilence(List<String> filters) {
    if (_disposed) return;
    _skipSilence = List<String>.of(filters);
    _schedule();
  }

  /// 登记均衡器（含 AutoEQ 的 Preamp）。传空列表表示关闭。
  void setEqualizer(List<String> filters) {
    if (_disposed) return;
    _equalizer = List<String>.of(filters);
    _schedule();
  }

  /// 登记交叉馈送。传空列表表示关闭。
  void setCrossfeed(List<String> filters) {
    if (_disposed) return;
    _crossfeed = List<String>.of(filters);
    _schedule();
  }

  /// 登记响度均衡。传空列表表示关闭。
  void setLoudness(List<String> filters) {
    if (_disposed) return;
    _loudness = List<String>.of(filters);
    _schedule();
  }

  /// 登记限幅器。传空列表表示关闭。
  void setLimiter(List<String> filters) {
    if (_disposed) return;
    _limiter = List<String>.of(filters);
    _schedule();
  }

  void _schedule() {
    if (_disposed) return;
    _timer?.cancel();
    // 首次调用立刻生效：用户拨开关时等一个 120ms 的合并窗口没必要，
    // 而这个窗口本来只为滑块拖动准备。
    if (_appliedSignature == null) {
      unawaited(_enqueue());
      return;
    }
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_enqueue());
    });
  }

  Future<void> _enqueue() {
    if (_disposed) return Future<void>.value();
    final next = _queue.then((_) => _apply()).catchError((_) {});
    _queue = next;
    // 队列跑完后唤醒等待者。放在 _apply 之后，读到的才是最新链路。
    unawaited(
      next.whenComplete(() {
        final pending = _pendingSettle;
        _pendingSettle = null;
        if (pending != null && !pending.isCompleted) pending.complete();
      }),
    );
    return next;
  }

  /// 等待当前登记的状态真正落到 mpv。
  ///
  /// 会把合并窗口也算进去：`setEqualizer(...)` 之后紧接着 `await settled`
  /// 必须等到这次写入完成，而不是只等到「上一次」写完。
  Future<void> get settled {
    if (_timer != null) {
      final pending = _pendingSettle ??= Completer<void>();
      return pending.future;
    }
    return _queue;
  }

  Future<void> _apply() async {
    if (_disposed) return;
    // 每轮失败放弃一个可选环节。四个环节最多降级四次，循环必然收敛。
    for (var attempt = 0; attempt < 5; attempt++) {
      if (_disposed) return;
      final chain = filters;
      final signature = chain.join(',');
      if (signature == _appliedSignature) return;
      try {
        await _writer.writeAf(chain);
        _appliedSignature = signature;
        return;
      } catch (error, stackTrace) {
        if (!_degradeOnce(error)) {
          AppLog.instance.record(
            'audio.chain',
            'af 写入失败：$error',
            level: AppLogLevel.warning,
            stackTrace: stackTrace,
          );
          return;
        }
      }
    }
  }

  /// 放弃一个可选环节，返回是否真的降级了。
  ///
  /// 顺序按「可牺牲程度」排：交叉馈送只是听感增强，响度归一有 ReplayGain
  /// 兜底，限幅器缺失只是有削波风险，跳过静音是次要便利——而均衡器是
  /// 用户亲手调过的曲线，任何情况下都不放弃。
  bool _degradeOnce(Object error) {
    if (!_crossfeedDegraded && _crossfeed.isNotEmpty) {
      _crossfeedDegraded = true;
      _logDegrade('crossfeed', error);
      return true;
    }
    if (!_loudnessDegraded && _loudness.isNotEmpty) {
      _loudnessDegraded = true;
      _logDegrade('dynaudnorm', error);
      return true;
    }
    if (!_limiterDegraded && _limiter.isNotEmpty) {
      _limiterDegraded = true;
      _logDegrade('alimiter', error);
      return true;
    }
    if (!_skipSilenceDegraded && _skipSilence.isNotEmpty) {
      _skipSilenceDegraded = true;
      _logDegrade('silenceremove', error);
      return true;
    }
    return false;
  }

  void _logDegrade(String name, Object error) {
    AppLog.instance.record(
      'audio.chain',
      '$name 不可用，已降级关闭（均衡器保留）：$error',
      level: AppLogLevel.warning,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}