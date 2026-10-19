// 文件说明：根导航的分段控件（iOS segmented control 风格）。
// 技术要点：整条是一块浅色轨道，选中项是一枚白色药丸，药丸用
// AnimatedPositioned 在四等分之间滑动——看上去像同一个实体在移动，
// 而不是四格各自淡入淡出。
//
// 这里刻意不出现强调色：导航是结构，颜色留给页面内容。选中项只靠
// 药丸的明度差和字重差表达，和「主题只染关键元素」的约定一致。

import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../theme/app_colors.dart';
import '../../l10n/app_strings.dart';
import 'pressable.dart';

/// 把根 tab 的选中态与切换回调传给页面顶部的分段控件。
class RootTabScope extends InheritedWidget {
  const RootTabScope({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required super.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;

  static RootTabScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RootTabScope>();
  }

  /// 只读一次，不建立依赖。给 [FrostedTabHeader.extent] 这类只要知道
  /// 「有没有壳层」的地方用——它们不关心选中项，不该跟着切 tab 重建。
  static RootTabScope? readOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<RootTabScope>();
  }

  @override
  bool updateShouldNotify(RootTabScope oldWidget) {
    // 只比选中项：onTap 每帧都是新闭包，比它会让整棵页面树每帧重建。
    // 旧闭包指向同一个 navigationShell，继续用也不会切错分支。
    return selectedIndex != oldWidget.selectedIndex;
  }
}

/// 分段控件总高。轨道内边距 3，药丸实际高 30。
const double kRootTabBarHeight = 36;
const double _kTrackPadding = 3;
const double _kTrackRadius = 10;

class RootTabBar extends StatelessWidget {
  const RootTabBar({super.key, this.height = kRootTabBarHeight});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scope = RootTabScope.maybeOf(context);
    final selected = (scope?.selectedIndex ?? 0).clamp(0, 3);
    final s = S.of(context);
    final labels = <String>[s.home, s.charts, s.playlists, s.settings];
    final isDark = AppColors.isDark(context);

    // 轨道要比背景深一档才看得出来是「凹槽」；深色下换成一层薄白。
    final trackColor = isDark
        ? const Color(0x12FFFFFF)
        : const Color(0x0D000000);
    final trackBorder = isDark
        ? const Color(0x1AFFFFFF)
        : const Color(0x0F000000);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inner = constraints.maxWidth - _kTrackPadding * 2;
          final segment = inner / labels.length;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(_kTrackRadius),
              border: Border.all(color: trackBorder, width: 0.8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(_kTrackPadding),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedPositioned(
                    duration: motionDuration(context, MotionDuration.normal),
                    curve: MotionCurve.iosSpring,
                    left: selected * segment,
                    top: 0,
                    bottom: 0,
                    width: segment,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0x28FFFFFF)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(
                          _kTrackRadius - _kTrackPadding,
                        ),
                        border: Border.all(
                          color: isDark
                              ? const Color(0x24FFFFFF)
                              : const Color(0x12000000),
                          width: 0.8,
                        ),
                        boxShadow: isDark
                            ? null
                            : const [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        Expanded(
                          child: Pressable(
                            semanticLabel: labels[i],
                            selected: i == selected,
                            // 分段控件里按下不缩放：药丸在滑动，格子再缩
                            // 一下会像两层动画打架。
                            scale: 1,
                            onTap: scope == null ? null : () => scope.onTap(i),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: motionDuration(
                                  context,
                                  MotionDuration.normal,
                                ),
                                curve: MotionCurve.iosSpring,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1,
                                  letterSpacing: 0.1,
                                  fontWeight: i == selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: i == selected
                                      ? AppColors.onScaffold(context)
                                      : AppColors.secondaryText(context),
                                ),
                                child: Text(
                                  labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
