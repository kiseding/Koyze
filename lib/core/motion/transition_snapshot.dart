import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 转场期间把页面画成一张位图，位移/缩放只作用在这张图上。
///
/// 不加这层时，整页在每个动画帧都要重新记录、重新光栅化：列表里的文字、
/// 封面、顶栏的磨砂都在跟着动，一次 280ms 的滑入要画十七遍。改成位图后
/// 每帧只剩一次贴图，页面里有多少内容都一样快。
///
/// 位图只在动画进行时存在，动画结束立刻丢掉并换回实时绘制，所以页面不会
/// 一直占着一张全屏纹理。
///
/// 动画进行到 [refreshDelay] 时重拍一次：动画开始后才加载出来的内容
/// （异步返回的列表、后到的封面）也能在动画里出现，而不是等落地才补上。
/// 重拍一次相当于把整页画一遍，所以只拍一次。
class TransitionSnapshot extends StatefulWidget {
  const TransitionSnapshot({
    super.key,
    required this.animations,
    required this.child,
    this.refreshDelay = const Duration(milliseconds: 160),
  });

  /// 其中任意一个在播放（forward / reverse）时使用快照。
  final List<Animation<double>> animations;
  final Widget child;
  final Duration refreshDelay;

  @override
  State<TransitionSnapshot> createState() => _TransitionSnapshotState();
}

class _TransitionSnapshotState extends State<TransitionSnapshot> {
  final SnapshotController _controller = SnapshotController();

  @visibleForTesting
  bool get debugSnapshotting => _controller.allowSnapshotting;
  final _PixelAlignedPainter _painter = _PixelAlignedPainter();
  Timer? _refresh;
  bool _releaseScheduled = false;

  bool get _animating => widget.animations.any(
    (animation) =>
        animation.status == AnimationStatus.forward ||
        animation.status == AnimationStatus.reverse,
  );

  void _sync(AnimationStatus _) {
    if (_animating) {
      _releaseScheduled = false;
      // 每次重新起动画都重拍一张：上一次动画期间页面内容可能已经变了。
      if (!_controller.allowSnapshotting) _controller.clear();
      _controller.allowSnapshotting = true;
      _refresh ??= Timer(widget.refreshDelay, _controller.clear);
      return;
    }

    _refresh?.cancel();
    _refresh = null;
    if (!_controller.allowSnapshotting || _releaseScheduled) return;

    // 动画状态在最终帧绘制前同步变更。把快照释放推迟到该帧提交后，
    // 避免同一帧里旧快照与已恢复的实时页面叠画或闪切。
    _releaseScheduled = true;
    final scheduler = SchedulerBinding.instance;
    scheduler.addPostFrameCallback((_) {
      _releaseScheduled = false;
      if (!mounted || _animating) return;
      _controller.allowSnapshotting = false;
    });
    scheduler.scheduleFrame();
  }

  @override
  void initState() {
    super.initState();
    for (final animation in widget.animations) {
      animation.addStatusListener(_sync);
    }
    _sync(AnimationStatus.dismissed);
  }

  @override
  void didUpdateWidget(TransitionSnapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final animation in oldWidget.animations) {
      animation.removeStatusListener(_sync);
    }
    for (final animation in widget.animations) {
      animation.addStatusListener(_sync);
    }
    _sync(AnimationStatus.dismissed);
  }

  @override
  void dispose() {
    _refresh?.cancel();
    for (final animation in widget.animations) {
      animation.removeStatusListener(_sync);
    }
    _controller.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _controller,
    // 子组件含平台视图等无法截图的内容时退回实时绘制，不报错。
    mode: SnapshotMode.permissive,
    autoresize: true,
    painter: _painter,
    child: widget.child,
  );
}

/// 把快照贴在整数个物理像素的位置上。
///
/// 默认贴图按逻辑坐标走：位置落在半个像素上时位图被重新采样，滑动中的
/// 页面发虚，动画结束换回实时绘制的那一帧还会错开半个像素，看起来一闪。
/// 对齐到物理像素后，缩放为 1 时快照与实时绘制逐像素相同。
class _PixelAlignedPainter extends SnapshotPainter {
  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) => painter(context, offset);

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    final canvas = context.canvas;
    final matrix = canvas.getTransform();
    // 只有平移与正的等比缩放（页面转场都是这种）时才能对齐，其余按原样画。
    final sx = matrix[0], sy = matrix[5];
    final aligned = matrix[1] == 0 && matrix[4] == 0 && sx > 0 && sy > 0;
    var origin = offset;
    if (aligned) {
      // 画布变换不含设备像素比（根图层单独按像素比缩放），取整要乘上它。
      double snap(double value, double scale, double translate) =>
          (((value * scale + translate) * pixelRatio).roundToDouble() /
                  pixelRatio -
              translate) /
          scale;
      origin = Offset(
        snap(offset.dx, sx, matrix[12]),
        snap(offset.dy, sy, matrix[13]),
      );
    }
    final source = Rect.fromLTWH(0, 0, sourceSize.width, sourceSize.height);
    // 缩放为 1 时 1:1 贴图，不需要过滤；缩放中用较好的过滤，减少锯齿。
    final exact =
        aligned &&
        ((sx * size.width * pixelRatio) - sourceSize.width).abs() < 0.5;
    canvas.drawImageRect(
      image,
      source,
      origin & size,
      Paint()
        ..filterQuality = exact ? FilterQuality.none : FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_PixelAlignedPainter oldPainter) => false;
}

/// 把页面转场的起点推迟到首帧画完。
///
/// 新页面推入的那一帧要先构建、布局，页面重的时候这一步就要几十毫秒。
/// 动画若从这一帧开始计时，下一帧会直接跳过一大截，看起来就是「卡一下」。
/// 推迟起点后动画从 0 平滑播到 1（总时长不变），代价只是起步晚一两帧。
abstract final class TransitionStart {
  static bool _holding = false;

  /// 当前是否处在「首帧还没画完」的那一帧里。
  static bool get holding => _holding;

  /// 在路由的 `didPush` 里调用：这一帧之内新起的前进动画都停在起点。
  static void hold() {
    if (_holding) return;
    _holding = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _holding = false);
  }

  static final Expando<_DeferredStart> _cache = Expando<_DeferredStart>();

  /// 包装转场动画：推入时延后起步（见 [hold]），手势与反向动画照常跟手。
  ///
  /// 必须按 [parent] 缓存：`transitionsBuilder` 每次重建都会重新调用这里，
  /// 每次返回新包装就会丢掉「首帧走到哪了」的记录，动画会原地跳一下。
  static Animation<double> of(Animation<double> parent) =>
      _cache[parent] ??= _DeferredStart(parent);
}

class _DeferredStart extends Animation<double>
    with AnimationWithParentMixin<double> {
  _DeferredStart(this.parent) {
    parent.addStatusListener((status) {
      if (status == AnimationStatus.forward && parent.value == 0) {
        // 从 0 起步的前进动画（页面推入）才需要推迟；中途续播不推迟。
        _fromZero = true;
      }
      if (status != AnimationStatus.forward) {
        _fromZero = false;
        _start = null;
      }
    });
  }

  @override
  final Animation<double> parent;

  /// 这次前进是从 0 开始的（只有推入时是这样，才延后起步）。
  bool _fromZero = false;

  /// 首帧画完之后原动画已经走到的位置；之后把 [_start]..1 映射成 0..1。
  double? _start;

  @override
  double get value {
    final current = parent.value;
    if (parent.status != AnimationStatus.forward) return current;
    if (TransitionStart._holding) return _fromZero ? 0 : current;
    if (!_fromZero) return current;
    final start = _start ??= current;
    return start >= 1 ? 1 : ((current - start) / (1 - start)).clamp(0.0, 1.0);
  }
}
