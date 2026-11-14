import 'package:flutter/widgets.dart';

/// 全屏播放器路由过渡进度（0 = 未打开，1 = 完全打开）。
/// MainScaffold 据此联动：底栏向下挤出、Tab 内容向上挤出、迷你栏扩张渐隐。
/// 拖拽关闭时也直接写该值，让整页元素跟手 morph，松手后由 API 收敛。
final ValueNotifier<double> playerRouteProgress = ValueNotifier<double>(0);

/// 拖拽关闭已接管后，禁止路由动画继续回写 [playerRouteProgress]，
/// 否则 Navigator 反向动画会先把已收拢的界面弹回全屏再播放关闭动效。
bool playerRouteDismissLocked = false;

/// 把全屏播放器路由过渡进度同步给主壳。
///
/// 关闭特效时路由时长是 [Duration.zero]，`forward()` 会在这层挂上监听之前
/// 同步走完。只靠监听会把进度留在 0：播放器正文不画出来，透明模态屏障
/// 却盖住整个页面，看起来就是什么都点不动。
class PlayerRouteProgressBridge extends StatefulWidget {
  const PlayerRouteProgressBridge({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  State<PlayerRouteProgressBridge> createState() =>
      _PlayerRouteProgressBridgeState();
}

class _PlayerRouteProgressBridgeState extends State<PlayerRouteProgressBridge> {
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 本组件由 `ModalRoute.buildTransitions` 创建，所在位置就在
    // `_ModalScopeStatus` 之下，能直接问到播放器这条路由本身；offstage 是
    // 实时读的，见 [_sync]。
    //
    // 首次同步放在这里而不是 initState：那时还没拿到路由，判断不了 offstage，
    // 而挂载这一帧恰好可能就是目标路由被 HeroController 藏起来的一帧。
    _route = ModalRoute.of(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant PlayerRouteProgressBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_sync);
      widget.animation.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    if (playerRouteDismissLocked) return;

    // 路由处于 offstage 时读到的动画值不可信。
    //
    // HeroController 每次 push 都会把**目标路由**临时 offstage 一帧：先在
    // 屏幕外完成目标页布局、量出 Hero 的终点位置，帧末再放回屏上（见
    // `HeroController._maybeStartHeroTransition`）。而
    // `ModalRoute.offstage = true` 会把该路由的动画代理换成
    // `kAlwaysCompleteAnimation`，value 恒为 1.0。
    //
    // 本组件正好在这一帧首次挂载并同步一次：读到 1.0 就当成"播放器已全屏"，
    // 主壳据此把 chrome 淡成全透明（MainScaffold 的 visibleProgress 只认
    // >0.92），而播放器此刻自己是 offstage 不画的——整屏只剩一层底色，
    // 一帧后才恢复，肉眼看就是打开播放器前闪一下黑。
    //
    // 隐藏态一律不写；帧末 offstage 复位时代理会换回真实动画并再通知一次，
    // 进度自然接上。
    if (_route?.offstage ?? false) return;

    // 曲线整形只在"路由自动动画"这一端做（CurvedAnimation 已套
    // easeOutCubic，与手势 settle 同曲线同时长）；拖动/左缘等手动
    // 驱动直接写值，播放器线性消费，保证跟手无固定路径。
    playerRouteProgress.value = widget.animation.value;
  }

  @override
  void dispose() {
    widget.animation.removeListener(_sync);
    playerRouteDismissLocked = false;
    playerRouteProgress.value = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
