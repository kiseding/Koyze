import 'package:flutter/material.dart';

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

  /// 大型页面转场（播放器展开、全屏页面）。
  static const Duration page = Duration(milliseconds: 480);

  /// 任何动画都不应超过的上限。
  static const Duration max = Duration(milliseconds: 600);
}

/// Central reduced-motion policy for widgets that cannot rely on implicit
/// animations being disabled by the framework.
bool reduceMotion(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  return media?.disableAnimations == true ||
      media?.accessibleNavigation == true;
}

Duration motionDuration(BuildContext context, Duration duration) =>
    reduceMotion(context) ? Duration.zero : duration;

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
