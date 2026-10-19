// 文件说明：根导航的顶部 tab 栏（液态玻璃胶囊）。
// 技术要点：只有胶囊本身采样背景，栏其余部分完全透明，滚动内容从胶囊两侧
// 和下方穿过——这才是"液态玻璃"，不是一条铺满宽度的毛玻璃板。

import 'package:flutter/material.dart';

import '../animations/micro_animations.dart';
import '../motion/motion_tokens.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../../l10n/app_strings.dart';
import 'liquid_glass.dart';
import 'pressable.dart';

/// 把根 tab 的选中态与切换回调传给页面顶部的 tab 栏。
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

  @override
  bool updateShouldNotify(RootTabScope oldWidget) {
    // 只比选中项：onTap 每帧都是新闭包，比它会让整棵页面树每帧重建。
    // 旧闭包指向同一个 navigationShell，继续用也不会切错分支。
    return selectedIndex != oldWidget.selectedIndex;
  }
}

/// 顶部 tab 胶囊：四个入口均分，选中项是一枚强调色药丸。
const double kRootTabBarHeight = 54;

class RootTabBar extends StatelessWidget {
  const RootTabBar({super.key, this.height = kRootTabBarHeight});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scope = RootTabScope.maybeOf(context);
    final selected = scope?.selectedIndex ?? 0;
    final s = S.of(context);
    final entries = <({IconData icon, IconData active, String label})>[
      (icon: Icons.home_outlined, active: Icons.home_rounded, label: s.home),
      (
        icon: Icons.leaderboard_outlined,
        active: Icons.leaderboard_rounded,
        label: s.charts,
      ),
      (
        icon: Icons.library_music_outlined,
        active: Icons.library_music_rounded,
        label: s.playlists,
      ),
      (
        icon: Icons.settings_outlined,
        active: Icons.settings_rounded,
        label: s.settings,
      ),
    ];

    return SizedBox(
      height: height,
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: AppGlass.shadowFor(
          context,
          style: AppGlassStyle.bar,
          emphasized: true,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: Row(
            children: [
              for (var i = 0; i < entries.length; i++)
                _Tab(
                  icon: entries[i].icon,
                  activeIcon: entries[i].active,
                  label: entries[i].label,
                  selected: i == selected,
                  onTap: scope == null ? null : () => scope.onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final isDark = AppColors.isDark(context);
    final muted = AppColors.secondaryText(context);

    return Expanded(
      child: Pressable(
        semanticLabel: label,
        selected: selected,
        onTap: onTap,
        scale: 0.94,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: motionDuration(context, MotionDuration.normal),
          curve: MotionCurve.iosSpring,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: isDark ? 0.20 : 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: isDark ? 0.42 : 0.30)
                  : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedIconSwitch(
                icon: selected ? activeIcon : icon,
                keyValue: selected ? activeIcon : icon,
                size: 20,
                color: selected ? accent : muted,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? accent : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
