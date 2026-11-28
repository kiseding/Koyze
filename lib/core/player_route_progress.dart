import 'package:flutter/scheduler.dart';
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
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    playerRouteDismissLocked = false;
    widget.animation.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant PlayerRouteProgressBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_sync);
      widget.animation.addListener(_sync);
      _scheduleSync();
    }
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _sync();
    });
  }

  void _sync() {
    if (playerRouteDismissLocked) return;
    // Hero 测量期间动画代理会暂时变成恒为 1 的动画；恢复真实代理时
    // 会再通知。零时长路由可能已在组件挂载前结束，因此挂载时也要补同步。
    if (_route?.offstage ?? false) return;
    // 进度同时被底下的主壳监听，不能在播放器的 build/layout 中写入。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _scheduleSync();
      return;
    }
    playerRouteProgress.value = widget.animation.value;
  }

  @override
  void dispose() {
    widget.animation.removeListener(_sync);
    playerRouteDismissLocked = false;
    // 最终反向 tick 通常已写入 0。手势锁定、移除路由等路径也要复位，
    // 在帧末通知主壳，避免它在 Navigator 正拆除路由时被标脏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!playerRouteDismissLocked) playerRouteProgress.value = 0;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
