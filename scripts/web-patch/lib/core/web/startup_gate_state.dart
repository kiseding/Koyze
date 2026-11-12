// 首启登录门控的全局可见状态（仅 Web 构建存在）。
//
// 门控页和侧栏在 widget 树里是兄弟节点：`IndependentSideRail` 包着
// `StartupCloudLoginPrompt`，所以登录页显示时侧栏依然占着左侧一条。
// 两边通过这个 provider 通信，让侧栏在门控期间整体让位。

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首启登录门控是否正占据整屏。
///
/// 默认 true：第一帧就假设门控在场，避免侧栏先闪一下再被登录页挤掉。
/// 门控判定完成（无需登录 / 已登录 / 用户已跳过）后置回 false。
final startupLoginGateActiveProvider = StateProvider<bool>((ref) => true);
