// 文件说明：材质的全局降级判定。
// 技术要点：把「系统或用户要求少一点效果」收敛成一个入口，玻璃面据此退实色。

import 'package:flutter/foundation.dart';
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

/// 当前是否正在滚动，供玻璃面在滚动期**降低**采样强度。
///
/// 注意这里降低的是「采样的强度」，不是「关掉采样」：玻璃面在滚动时仍然
/// 真实采样背后并模糊，只是把卷积核半径乘一个折扣系数。滚动中背景每帧
/// 都在变，`BackdropFilter` 必须每帧重新捕获并卷积一次背后整屏，一屏
/// 四五块大玻璃确实贵；但直接把采样关掉会让玻璃在滚动的瞬间变成一块纯
/// 透明混合，用户看得见「玻璃没了」——那是降级，不是优化。
///
/// 折扣取 [scrollBlurDiscount]（0.5）：高斯卷积的代价随半径超线性增长，
/// 半径减半省下的时间远不止一半，而滚动时整屏都在运动、材质细节本来就被
/// 运动糊掉了，半径减半肉眼几乎不可辨。手指抬起后立刻恢复满档。
///
/// 用 ambient 通知而不是让每个玻璃面各自监听滚动：一屏十块面就是十个
/// `ScrollNotification` 监听器，而且它们还得各自去猜「哪个滚动视图才是我的」。
/// 由滚动视图自己在开始/结束时置位，玻璃面只读一个 bool。
abstract final class GlassScrollActivity {
  /// 滚动期模糊半径的折扣系数。
  ///
  /// 有意留得比「完全关掉」高很多：这个值决定滚动时玻璃还剩多少质感。
  /// 0.5 是实测折中——再低就开始能看出「滚的时候糊度跳变」。
  static const double scrollBlurDiscount = 0.5;

  static final ValueNotifier<bool> _scrolling = ValueNotifier<bool>(false);

  static ValueListenable<bool> get listenable => _scrolling;

  static bool get isScrolling => _scrolling.value;

  /// 此刻该用的模糊折扣：静止 1.0，滚动中 [scrollBlurDiscount]。
  static double get blurFactor => _scrolling.value ? scrollBlurDiscount : 1.0;

  /// 滚动开始时置 true、结束时置 false。
  ///
  /// 用 [ScrollNotification] 的 `ScrollStartNotification` /
  /// `ScrollEndNotification` 驱动；`UserScrollNotification` 会在惯性滑动
  /// 结束时滞后一帧，静止判定的边界不如 End 干脆。
  static void set(bool value) {
    if (_scrolling.value == value) return;
    _scrolling.value = value;
  }

  @visibleForTesting
  static void reset() => set(false);
}

/// 把子树里的滚动事件接到 [GlassScrollActivity]。
///
/// 包在滚动视图外面即可，页内所有玻璃面自动跟随。不包也不会错——只是失去
/// 「滚动期降低采样」这一档优化，玻璃仍然正常工作。
///
/// 只认 `depth == 0` 的通知：嵌套滚动视图（比如横向的图片条）自己也有
/// Start/End，如果全都接，内层滚到底之后外层还在滚的瞬间会被误判成「停了」。
class GlassScrollObserver extends StatelessWidget {
  const GlassScrollObserver({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        switch (notification) {
          case ScrollStartNotification():
            GlassScrollActivity.set(true);
          case ScrollEndNotification():
            GlassScrollActivity.set(false);
          default:
            break;
        }
        return false;
      },
      child: child,
    );
  }
}
