import 'package:flutter/foundation.dart';

/// 全屏播放器路由过渡进度（0 = 未打开，1 = 完全打开）。
/// MainScaffold 据此联动：底栏向下挤出、Tab 内容向上挤出、迷你栏扩张渐隐。
final ValueNotifier<double> playerRouteProgress = ValueNotifier<double>(0);
