import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/audio_handler.dart';
import '../../../../core/audio/audio_spectrum.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/player_spectrum_settings.dart';
import 'player_spectrum_painter.dart';

/// 播放页上的实时频谱条。
///
/// 位置固定在「当前歌词行」与「进度条」之间——那是播放页唯一一段既不挡
/// 封面、也不和任何手势冲突、而且语义连贯（歌词 → 律动 → 进度）的空隙。
///
/// 三条硬约束：
///
/// 1. **不动原有布局**。引擎不支持时（Web / just_audio 回退）整块返回零
///    尺寸，不留占位，页面与加这个功能之前逐像素相同。
/// 2. **不常驻动画**。只在真有数据时挂 [Ticker]；暂停、静音、播放结束时
///    停掉，不在后台空转。
/// 3. **不参与空间分配**。高度固定，不放进任何 `Expanded`，因此不会挤压
///    封面或控制区的比例。
class PlayerSpectrumStrip extends ConsumerStatefulWidget {
  const PlayerSpectrumStrip({
    super.key,
    this.style = SpectrumStyle.bars,
    this.height = 44,
    this.horizontalInset = 0,
    this.accentOverride,
    this.sourceOverride,
  });

  /// 绘制样式。
  final SpectrumStyle style;

  /// 条带高度。竖屏取 44；横屏信息列更紧，由外部传更小的值。
  final double height;

  /// 左右内缩。
  ///
  /// 对齐目标是**进度条上方那一行的时间标签**（当前时间 / 总时长），
  /// 不是进度条轨道本身。两个理由：
  ///
  /// 1. 语义上，频谱和时间标签都在回答「这一首歌的进度」这件事，同一列
  ///    元素应该共享同一条左右基准线；对着一根细细的轨道边对齐，反而
  ///    让频谱显得比它上面那行字更宽。
  /// 2. 视觉上，轨道两端是圆头，左侧还有一个小圆点；把频谱对到圆点或
  ///    圆头的外沿，右边就会多出一截空白，看起来像没对齐。
  ///
  /// 调用方传入与时间标签一致的水平内缩即可。
  final double horizontalInset;

  /// 强制指定主色。为空时取主题强调色。
  final Color? accentOverride;

  /// 指定数据源。为空时从全局 [audioHandler] 取。
  ///
  /// 生产代码不需要传；留着是为了测试能塞一个合成帧的源进来——否则频谱
  /// 条的补间、峰值衰减、ticker 停机这些逻辑只能靠肉眼在真机上验。
  final AudioSpectrumSource? sourceOverride;

  @override
  ConsumerState<PlayerSpectrumStrip> createState() => _PlayerSpectrumStripState();
}

class _PlayerSpectrumStripState extends ConsumerState<PlayerSpectrumStrip>
    with SingleTickerProviderStateMixin {
  /// 数据源。引擎重建后 handler 会换一个新的 source，所以不跨帧缓存。
  AudioSpectrumSource? _source;
  StreamSubscription<SpectrumFrame>? _subscription;

  /// 目标值（mpv 最新一帧）与显示值（逐帧补间后的值）。
  List<double> _target = const [];
  List<double> _display = const [];
  List<double> _peak = const [];

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  DateTime? _lastFrameAt;

  /// 数据版本号，每次幅值真的变了就 +1。
  ///
  /// 补间是原地改 [_display] 的元素，新旧 painter 会持有同一个 List，所以
  /// `shouldRepaint` 只能靠这个数字判断——详见 [SpectrumPainter.revision]。
  int _revision = 0;

  /// 订阅成功后的「一直没有帧」探测。
  ///
  /// 频谱条最难受的失败是「静态」：形状画出来了但永远不动。它可能是补间
  /// 没触发重绘（本仓库踩过），也可能是 mpv 根本不发 fft 帧（libmpv 太老、
  /// 没有 `pcm-tap-frame` 属性）。后者在 UI 上无法区分，只能打一行日志，
  /// 让排查的人一眼看出是哪一类。
  Timer? _firstFrameTimer;

  /// 引擎是否支持。启动早期 `audioHandler` 是未初始化的 late 变量，
  /// 读它会抛；那时先当作不支持，下一次依赖变化再判。
  bool _supported = false;

  /// 启动早期已重试的次数，见 [_scheduleAttachRetry]。
  int _attachAttempts = 0;

  /// 系统是否要求减弱动效。缓存下来是因为 [_onFrame] 要据此决定不启动
  /// ticker——那里不在 build 里，读 `MediaQuery` 会建立意外的依赖。
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) _stopTicker();
    // 每次依赖变化都重新探一次：从 Web 回退切换、或引擎重建后
    // source 会换实例，必须重新订阅。
    _attach();
  }

  @override
  void didUpdateWidget(covariant PlayerSpectrumStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sourceOverride, widget.sourceOverride)) {
      // 换了注入源就重订：测试里会中途换源验证取消是否干净。
      unawaited(_subscription?.cancel());
      _subscription = null;
      _source = null;
      _attach();
    }
  }

  void _attach() {
    AudioSpectrumSource? source;
    final override = widget.sourceOverride;
    if (override != null) {
      source = override;
    } else {
      try {
        final handler = audioHandler;
        if (handler is LxAudioHandler) source = handler.spectrum;
      } catch (_) {
        // 启动引导还没完成，`audioHandler` 是未初始化的 late 变量。依赖变化
        // 不一定会再来（主题、MediaQuery 都没变的话），所以自己安排有限次
        // 重试，而不是指望有人把我们重建一次。
        _scheduleAttachRetry();
        return;
      }
    }

    if (source == null || !source.available) {
      _markSupported(false);
      return;
    }
    if (identical(source, _source)) return;

    unawaited(_subscription?.cancel());
    _source = source;
    _attachAttempts = 0;
    _markSupported(true);
    _subscription = source.frames.listen(
      _onFrame,
      onError: (_) {},
      // 引擎重建（`_replaceNativePlayer`）会把旧 source 关掉并且不给任何
      // 依赖变化，只能靠流结束这个信号重新挂到新引擎上。
      onDone: () {
        if (mounted) _scheduleAttachRetry();
      },
    );
    _armFirstFrameProbe();
  }

  /// 启动早期的重试。上限 20 次（约两秒），失败到底就静默放弃——
  /// 频谱是装饰，不值得为它一直占着一帧一帧的回调。
  void _scheduleAttachRetry() {
    if (_attachAttempts >= 20) return;
    _attachAttempts++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _attach();
    });
  }

  /// 订阅建立后 3 秒仍一帧未收到，打一行日志。
  ///
  /// 只在「从未收到过帧」时触发，所以正常暂停（之前收到过）不会误报。
  void _armFirstFrameProbe() {
    _firstFrameTimer?.cancel();
    _firstFrameTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _lastFrameAt != null) return;
      debugPrint(
        '[spectrum] 已订阅但 3 秒内没有 fft 帧：'
        '检查 libmpv 是否提供 pcm-tap-frame（需 v0.41+），以及此时是否在播放',
      );
    });
  }

  /// 改「是否支持」并保证不在构建阶段调 `setState`。
  ///
  /// [initState] / [didChangeDependencies] 都发生在 build 之前，那时
  /// `setState` 会触发「setState() called during build」；而这两个回调之后
  /// 紧接着就是一次 build，直接改字段即可。
  void _markSupported(bool value) {
    if (_supported == value) return;
    if (!mounted ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
      _supported = value;
      return;
    }
    setState(() => _supported = value);
  }

  void _onFrame(SpectrumFrame frame) {
    if (!mounted) return;
    _lastFrameAt = DateTime.now();
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    final bands = frame.bands;
    if (bands.isEmpty) return;

    if (_target.length != bands.length) {
      // 柱数变化（例如以后调小 bandCount）时整体重置，避免下标错位。
      _target = List<double>.of(bands);
      _display = List<double>.of(bands);
      _peak = List<double>.of(bands);
    } else {
      _target = List<double>.of(bands);
    }
    _revision++;

    // 减弱动效时保留数据但不逐帧重绘——那条细线本身不需要补间。
    if (_reduceMotion) {
      setState(() {});
      return;
    }
    _ensureTicker();
  }

  void _ensureTicker() {
    if (_ticker != null) return;
    final ticker = createTicker(_tick);
    _ticker = ticker;
    _lastTick = Duration.zero;
    ticker.start();
  }

  void _stopTicker() {
    _ticker?.dispose();
    _ticker = null;
  }

  /// 逐帧补间。
  ///
  /// 30Hz 的数据配 120Hz 的屏幕，直接画最新值会让柱子在两次数据之间冻住；
  /// 这里用与帧率无关的指数逼近把台阶抹平。
  ///
  /// 上升要快、下降要慢，但**都不能慢到吃掉频段差异**。之前的
  /// 0.34 / 0.11 是叠在 mpv 内部平滑之上的第二层平滑，两层一叠，各频段
  /// 之间的差距在到达屏幕前就被抹平了——用户看到的就是「所有柱子都
  /// 差不多高」，听不出音调变化。
  ///
  /// 现在 mpv 侧的 `attackSmoothing` / `releaseSmoothing` 已经降到很轻
  /// （见 `kSpectrumSettings`），补间的阻尼就可以调小：上升 0.62 让瞬态
  /// 基本跟得上，下降 0.22 仍留一点拖影，但不至于把相邻频段糊成一片。
  void _tick(Duration elapsed) {
    if (_display.isEmpty) {
      _stopTicker();
      return;
    }

    final delta = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final dt = delta.clamp(0.0, 0.06);

    final display = _display;
    final peak = _peak;
    var changed = false;

    for (var i = 0; i < display.length; i++) {
      final target = i < _target.length ? _target[i] : 0.0;
      final current = display[i];
      final rise = target > current;
      final rate = rise ? 0.62 : 0.22;
      final factor = 1 - math.pow(1 - rate, dt * 60).toDouble();
      final next = current + (target - current) * factor;
      if ((next - current).abs() > 0.0006) {
        display[i] = next;
        changed = true;
      } else if (current != target) {
        display[i] = target;
        changed = true;
      }

      // 峰值帽：跟随上升，之后以恒定速度回落，而不是跟着柱子指数衰减。
      if (display[i] > peak[i]) {
        peak[i] = display[i];
        changed = true;
      } else if (peak[i] > 0) {
        final decayed = peak[i] - dt * 0.55;
        peak[i] = decayed < display[i] ? display[i] : decayed;
        changed = true;
      }
    }

    if (changed && mounted) {
      _revision++;
      setState(() {});
    }

    // 数据断了（暂停 / 播放结束 / 页面不可见）就停：没有新帧时补间终将
    // 落到目标，继续跑 ticker 只是空转。
    final last = _lastFrameAt;
    final stale = last == null || DateTime.now().difference(last).inMilliseconds > 400;
    if (stale && !changed) _stopTicker();
  }

  @override
  void dispose() {
    _stopTicker();
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 不支持就彻底不参与布局。返回 SizedBox.shrink 而不是留白，
    // 「其它元素不能动」这条约束才能成立。
    if (!_supported) return const SizedBox.shrink();

    final accent = widget.accentOverride ?? AppColors.accentOf(context);
    final track = AppColors.cardBorder(context);

    if (_reduceMotion) {
      // 减弱动效：保留位置与语义，但不逐帧重绘。
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalInset),
        child: SizedBox(
          height: widget.height,
          child: Center(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalInset),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: SpectrumPainter(
              display: _display,
              peak: _peak,
              style: widget.style,
              accent: accent,
              trackColor: track,
              revision: _revision,
            ),
          ),
        ),
      ),
    );
  }
}