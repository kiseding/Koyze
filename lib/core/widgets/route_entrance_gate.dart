import 'package:flutter/widgets.dart';

/// 监听当前路由的入场动画，用 `builder(context, settled)` 拿到「是否已经播完」。
///
/// 只做通知，不推迟构建：调用方自己决定入场期间用什么替代（封面就是先留白）。
///
/// 判断完成时机不能直接信 `ModalRoute.animation`：挂载这一帧可能正赶上
/// `HeroController` 把目标路由 `offstage` 一帧去屏幕外量 Hero 终点，此时动画
/// 代理被换成 `kAlwaysCompleteAnimation`（值恒 1.0、status 恒 completed），
/// 照着判断会在动效刚开始时就当成「已播完」。所以等帧末 offstage 复位后再看，
/// 复位比回调更晚时重试几帧（零时长过渡也只多等 1~2 帧）。
class RouteEntranceGate extends StatefulWidget {
  const RouteEntranceGate({super.key, required this.builder});

  /// [settled] 为 true 表示入场动画已播完（或这条路由本来就没有动画）。
  final Widget Function(BuildContext context, bool settled) builder;

  @override
  State<RouteEntranceGate> createState() => _RouteEntranceGateState();
}

class _RouteEntranceGateState extends State<RouteEntranceGate> {
  static const int _maxOffstageRetries = 8;

  ModalRoute<Object?>? _route;
  Animation<double>? _routeAnimation;
  bool _settled = false;
  int _offstageRetries = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final animation = _route?.animation;
    if (!identical(animation, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_handleStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_handleStatus);
      _checkAfterFrame();
    }
    // 根本不在路由里，没什么可等的。
    if (_route == null) _settle();
  }

  void _checkAfterFrame() {
    if (!mounted || _settled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _settled) return;
      final route = _route;
      if (route != null && route.offstage) {
        if (_offstageRetries < _maxOffstageRetries) {
          _offstageRetries += 1;
          _checkAfterFrame();
        }
        return;
      }
      _settleIfFinished();
    });
  }

  void _settleIfFinished() {
    final animation = _route?.animation;
    // completed：动画已经播完（恢复的页面、零时长过渡）；
    // null：这条路由没有动画，等价于已播完。
    if (animation == null || animation.status == AnimationStatus.completed) {
      _settle();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_route?.offstage ?? false) return;
    _settle();
  }

  void _settle() {
    if (_settled) return;
    _settled = true;
    setState(() {});
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _settled);
}
