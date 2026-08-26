import 'package:flutter/foundation.dart';

/// 全屏播放器路由过渡进度（0 = 未打开，1 = 完全打开）。
/// MainScaffold 据此联动：底栏向下挤出、Tab 内容向上挤出、迷你栏扩张渐隐。
/// 拖拽关闭时也直接写该值，让整页元素跟手 morph，松手后由 API 收敛。
final ValueNotifier<double> playerRouteProgress = ValueNotifier<double>(0);

/// 拖拽关闭已接管后，禁止路由动画继续回写 [playerRouteProgress]，
/// 否则 Navigator 反向动画会先把已收拢的界面弹回全屏再播放关闭动效。
bool playerRouteDismissLocked = false;
