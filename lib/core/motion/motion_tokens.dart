import 'package:flutter/material.dart';

import '../performance/low_memory.dart';

/// 全局 Motion Design Tokens。
/// 所有页面/组件动画统一引用这里，禁止各页面自造 Duration/Curve。
class MotionDuration {
  const MotionDuration._();

  /// 微交互（按压反馈、图标切换、thumb 放大）。
  static const Duration micro = Duration(milliseconds: 150);

  /// 普通过渡（状态切换、歌词高亮、开关）。
  static const Duration normal = Duration(milliseconds: 280);

  /// Container Transform / Shared Axis 等页面过渡。
  static const Duration container = Duration(milliseconds: 400);

  /// 大型页面转场（普通全屏页面）。
  static const Duration page = Duration(milliseconds: 480);

  /// 弹窗进场：压暗、模糊和面板弹出共用一条时间线。
  static const Duration dialog = Duration(milliseconds: 320);

  /// 弹窗退场比进场快，避免关闭时拖沓。
  static const Duration dialogReverse = Duration(milliseconds: 180);

  /// 底部弹窗进场。比普通过渡慢，留给面板滑动和内容淡入。
  static const Duration sheet = Duration(milliseconds: 420);

  /// 底部弹窗退场。
  static const Duration sheetReverse = Duration(milliseconds: 260);

  /// iOS 风格播放器展开/收起。比普通页面慢，给封面、背景和内容 stagger 留足时间。
  static const Duration player = Duration(milliseconds: 720);

  /// iOS 风格播放器关闭。略快于打开，但仍保持 spring-like 连贯感。
  static const Duration playerReverse = Duration(milliseconds: 560);

  /// 任何普通动画都不应超过的上限；播放器转场有单独 token。
  static const Duration max = Duration(milliseconds: 600);
}

/// Central reduced-motion policy for widgets that cannot rely on implicit
/// animations being disabled by the framework.
bool reduceMotion(BuildContext context) {
  if (LowMemory.active) return true;
  final media = MediaQuery.maybeOf(context);
  return media?.disableAnimations == true ||
      media?.accessibleNavigation == true;
}

Duration motionDuration(BuildContext context, Duration duration) =>
    reduceMotion(context) ? Duration.zero : duration;

/// Route and menu transitions have no [BuildContext] when their duration is
/// read. The effects switch is enough there.
Duration effectsDuration(Duration duration) =>
    LowMemory.active ? Duration.zero : duration;

AnimationStyle effectsAnimationStyle({
  Duration duration = MotionDuration.normal,
  Duration reverseDuration = MotionDuration.micro,
  Curve curve = MotionCurve.easeOut,
  Curve reverseCurve = MotionCurve.easeIn,
}) {
  return AnimationStyle(
    duration: effectsDuration(duration),
    reverseDuration: effectsDuration(reverseDuration),
    curve: curve,
    reverseCurve: reverseCurve,
  );
}

class MotionCurve {
  const MotionCurve._();

  /// 默认缓出：进入/展开/出现。
  static const Curve easeOut = Curves.easeOutCubic;

  /// 缓入缓出：往返、收起。
  static const Curve easeInOut = Curves.easeInOutCubic;

  /// 缓入：退出/收起时用。
  static const Curve easeIn = Curves.easeInCubic;

  /// 强调感（收藏 q 弹等少量点缀）。
  static const Curve emphasize = Curves.easeOutBack;

  /// iOS-like 的慢速减速曲线：接近原生 spring 的“有惯性但不弹”的观感。
  static const Curve iosSpring = Cubic(0.20, 0.00, 0.00, 1.00);

  /// 弹窗弹出：终点略微过冲，收尾时面板会“落”回 100%，比纯 easeOut 有实体感。
  static const Curve dialogIn = Cubic(0.20, 1.16, 0.32, 1.00);

  /// 底部弹窗上滑：几乎无过冲，只保留最后一段减速。
  static const Curve sheetIn = Cubic(0.16, 1.00, 0.30, 1.00);

  /// 快速的 quint 级减速，用于内容入场与色块扩展。
  static const Curve easeOutQuart = Cubic(0.25, 1.00, 0.50, 1.00);
}

class MotionDistance {
  const MotionDistance._();

  /// 轻量位移（歌词行、列表项反馈）。
  static const double subtle = 4;

  /// 标准位移（页面内容滑入）。
  static const double standard = 12;

  /// 页面级位移（Shared Axis 方向感）。
  static const double page = 24;
}

class MotionScale {
  const MotionScale._();

  /// 按压反馈。
  static const double press = 0.96;

  /// 图标切换进入。
  static const double iconIn = 0.9;

  /// 内容淡入。
  static const double contentIn = 0.98;

  /// 卡片展开起点（对应小卡片）。
  static const double cardFrom = 0.95;
}
