import 'package:flutter/widgets.dart';

/// 等当前路由的入场动画放完，再构建 [child]。
///
/// 卡片展开转场会把目标页的**首帧**直接画进动效窗口：那一帧要建出首屏
/// 十几行列表、发起十几张封面请求、跑完首屏分页解码。列表越长这帧越贵，
/// 动效会在开头就顿住甚至看起来卡死。
///
/// 把重内容包在这里，转场期间只画页面骨架（底色 + 顶栏），动效就能一直
/// 跑在满帧上；动画结束后才挂载列表，那一帧的停顿落在「已经全屏」之后，
/// 肉眼只会觉得内容晚了一拍出现，而不是动效卡住。
///
/// 没挂在路由上（比如直接放进 [MaterialApp.home]）或动效被关掉时（零时长
/// 过渡的 status 一上来就是 completed），会立刻构建 [child]，不做任何推迟。
class DeferredUntilRouteSettled extends StatefulWidget {
  const DeferredUntilRouteSettled({
    super.key,
    required this.child,
    this.placeholder = const SizedBox.expand(),
    this.onSettled,
  });

  /// 动效结束后才挂载的内容。
  final Widget child;

  /// 挂载前占位。默认铺满，避免布局塌陷导致顶栏/悬浮控件跳位。
  final Widget placeholder;

  /// 挂载后回调一次（帧末触发）。页面若依赖「列表已挂载」才能做的定位、
  /// 滚动，在这里补做。
  final VoidCallback? onSettled;

  @override
  State<DeferredUntilRouteSettled> createState() =>
      _DeferredUntilRouteSettledState();
}

class _DeferredUntilRouteSettledState extends State<DeferredUntilRouteSettled> {
  /// `offstage` 期间不能用动画值判断（见 [_checkAfterFrame]），最多重试几帧。
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
    if (_route == null) _settle(notify: false);
  }

  /// 挂载这一帧可能正赶上 `HeroController` 把目标路由 `offstage` 一帧去屏幕外
  /// 量 Hero 终点（和 `playerRouteProgress` 那个黑帧 bug 同一个机制）：
  /// 此时 `ModalRoute.animation` 被换成 `kAlwaysCompleteAnimation`，值恒为
  /// 1.0、status 恒为 completed，直接信它会在动效刚开始时就把内容全建出来。
  /// 所以要等帧末 offstage 复位后再判断；复位可能比本回调更晚，就重试几帧。
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
    // completed 说明动画已经播完（恢复的页面、零时长过渡）；
    // null 说明这条路由没有动画，等价于已播完。
    if (animation == null || animation.status == AnimationStatus.completed) {
      _settle();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_route?.offstage ?? false) return;
    _settle();
  }

  void _settle({bool notify = true}) {
    if (_settled) return;
    _settled = true;
    if (!notify) return;
    // 状态回调可能来自动画 tick（帧中），直接 setState 是安全的；但 onSettled
    // 往往带滚动/定位，放到帧末，等这一帧的布局落地后再做。
    setState(() {});
    final callback = widget.onSettled;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _settled ? widget.child : widget.placeholder;
}
