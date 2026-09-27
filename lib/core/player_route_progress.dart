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
  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_sync);
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
