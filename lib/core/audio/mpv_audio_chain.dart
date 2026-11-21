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
/// * 跳过静音在前——它要判断「这一段是不是空白」，必须在均衡器抬过噪声
///   基底之前看到原始信号，否则 −50 dB 的静音被 +12 dB 的低频增益抬到
///   −38 dB，就再也判不成静音了。
/// * 均衡器在后，其余环节（限幅等）未来排在最后。
List<String> composeMpvFilterChain({
  required List<String> skipSilence,
  required List<String> equalizer,
  bool skipSilenceDegraded = false,
}) {
  final chain = <String>[];
  if (!skipSilenceDegraded) chain.addAll(skipSilence);
  chain.addAll(equalizer);
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

  /// silenceremove 写失败后永久降级：宁可没有跳过静音，也不能让它连带
  /// 把均衡器一起拖死。只在第一次失败时记一条日志，不刷屏。
  bool _skipSilenceDegraded = false;

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

  /// 当前生效的链路（已降级则不含跳过静音）。诊断与测试用。
  List<String> get filters => composeMpvFilterChain(
    skipSilence: _skipSilence,
    equalizer: _equalizer,
    skipSilenceDegraded: _skipSilenceDegraded,
  );

  bool get skipSilenceDegraded => _skipSilenceDegraded;

  /// 登记跳过静音。传空列表表示关闭。
  void setSkipSilence(List<String> filters) {
    if (_disposed) return;
    _skipSilence = List<String>.of(filters);
    _schedule();
  }

  /// 登记均衡器。传空列表表示关闭或全平。
  void setEqualizer(List<String> filters) {
    if (_disposed) return;
    _equalizer = List<String>.of(filters);
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
    final signature = filters.join(',');
    if (signature == _appliedSignature) return;
    try {
      await _writer.writeAf(filters);
      _appliedSignature = signature;
    } catch (error, stackTrace) {
      // 失败可能是 silenceremove 本身不被这份 libmpv 支持。降级后重试一次，
      // 保住均衡器——它才是用户主动调过的那条曲线。
      final canDegrade =
          !_skipSilenceDegraded && _skipSilence.isNotEmpty;
      if (!canDegrade) {
        AppLog.instance.record(
          'audio.chain',
          'af 写入失败：$error',
          level: AppLogLevel.warning,
          stackTrace: stackTrace,
        );
        return;
      }
      _skipSilenceDegraded = true;
      AppLog.instance.record(
        'audio.chain',
        'silenceremove 不可用，跳过静音降级关闭（均衡器保留）：$error',
        level: AppLogLevel.warning,
        stackTrace: stackTrace,
      );
      final fallback = filters;
      if (_disposed) return;
      try {
        await _writer.writeAf(fallback);
        _appliedSignature = fallback.join(',');
      } catch (retryError, retryStack) {
        AppLog.instance.record(
          'audio.chain',
          'af 降级后仍然失败：$retryError',
          level: AppLogLevel.warning,
          stackTrace: retryStack,
        );
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}