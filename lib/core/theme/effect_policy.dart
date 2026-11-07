// 文件说明：材质的全局降级判定。
// 技术要点：把「系统或用户要求少一点效果」收敛成一个入口，玻璃面据此退实色。

import 'package:flutter/widgets.dart';

import '../performance/low_memory.dart';

/// 玻璃渲染质量档位。
///
/// 这是材质层的统一协议：页面不需要知道底层使用的是 BackdropFilter、轻量
/// Shader 还是静态叠层，后续替换渲染后端时只需要改材质实现。
enum GlassQuality {
  /// 静止时的完整实时玻璃：背景模糊、饱和度和高光全部开启。
  premium,

  /// 降低模糊半径和色彩处理，但仍然实时采样背景。
  standard,

  /// 不读取背景，只保留半透明染色、薄膜高光和边缘。
  minimal,

  /// 接近不透明的实色面，适合低内存、无障碍和关闭效果的环境。
  off,
}

/// 根据系统和用户偏好收敛最终材质档位。
///
/// 滚动期由调用方主动传入 [scrolling]，默认只把高成本的实时档降到
/// [GlassQuality.minimal]；已经明确要求更低档位时不会被提升。
GlassQuality resolveGlassQuality(
  BuildContext context, {
  GlassQuality requested = GlassQuality.premium,
  bool scrolling = false,
}) {
  if (prefersFlatSurfaces(context)) return GlassQuality.off;
  if (scrolling &&
      (requested == GlassQuality.premium ||
          requested == GlassQuality.standard)) {
    return GlassQuality.minimal;
  }
  return requested;
}

/// 是否应该把玻璃面画成实色，而不是把背后的内容糊一层。
///
/// 三个信号任一成立就退实色：
///
/// * 用户在设置里关掉了「特效」（[LowMemory.active]）。这是应用内的开关，
///   低内存机型默认打开。
/// * 系统开了「增强对比度」（[MediaQueryData.highContrast]）。玻璃底色很淡，
///   背后是封面或彩色卡片时正文对比度会掉下去，而这正是「增强对比度」要治
///   的问题——这类用户本来就不该看到半透明材质。
/// * 系统关掉了动画（[MediaQueryData.disableAnimations]），Android 的省电模式
///   也会置上这一位。和 `showKoyzeDialog` 的处理保持一致：那台机器上，全宽
///   实时采样换来的只是每帧多花几毫秒。
///
/// 判定只在上述情况成立，所以对默认设置的设备**没有任何外观影响**：该糊的地
/// 方照糊，一个像素都不动。
///
/// 与 `reduceMotion` 的分工：那个管的是动画时长，这个管的是材质本身。减少动效
/// 不等于讨厌玻璃，但用户既然把系统的「效果」全关了，还每帧替他算一遍模糊就
/// 说不过去了。
bool prefersFlatSurfaces(BuildContext context) {
  if (LowMemory.active) return true;
  final media = MediaQuery.maybeOf(context);
  if (media == null) return false;
  return media.highContrast || media.disableAnimations;
}
