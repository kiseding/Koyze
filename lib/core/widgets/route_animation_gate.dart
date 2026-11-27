import 'package:flutter/widgets.dart';

/// 让某个效果知道「所属路由正在播转场动画」。
///
/// [builder] 的第二个参数为 true 表示这条路由正在走前进/返回动画。
/// 页面推入的那一帧就是 from 状态：整页都在移动，重效果（背景滤镜、
/// 大面积阴影）放到这时候画一次都嫌贵，而且转场期间页面本来会换成
/// 一张位图，带着背景滤镜的位图既贵又采不到正确背景。
///
/// 和 `RouteEntranceGate` 的区别：那个只等「动画播完」这一个时刻，
/// 适用于"入场结束再做某事"；这里双向都跟，动画进行中是 true，停下
/// 立刻是 false。没有动画的路由（根壳层、零时长过渡）第一次就是 false。
class RouteAnimationGate extends StatefulWidget {
  const RouteAnimationGate({super.key, required this.builder});

  final Widget Function(BuildContext context, bool animating) builder;

  @override
  State<RouteAnimationGate> createState() => _RouteAnimationGateState();
}

class _RouteAnimationGateState extends State<RouteAnimationGate> {
  ModalRoute<Object?>? _route;
  Animation<double>? _animation;

  bool get _animating {
    final status = _animation?.status;
    return status == AnimationStatus.forward ||
        status == AnimationStatus.reverse;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final animation = _route?.animation;
    if (!identical(animation, _animation)) {
      _animation?.removeStatusListener(_handleStatus);
      _animation = animation;
      animation?.addStatusListener(_handleStatus);
    }
    // 这里不用 setState：依赖变化之后本来就会重建。
    _animatingNow = _animating;
  }

  bool _animatingNow = false;

  void _handleStatus(AnimationStatus status) {
    final next = _animating;
    if (next == _animatingNow) return;
    setState(() => _animatingNow = next);
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_handleStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _animatingNow);
}
