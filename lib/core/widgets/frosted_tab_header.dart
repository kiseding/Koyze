import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'gradient_bar_backgrounds.dart';
import 'liquid_glass.dart';
import 'pressable.dart';
import 'root_tab_bar.dart';
import 'origo_chrome.dart';

/// 根页面的顶部 chrome。
///
/// 在根壳层里（存在 [RootTabScope]）它渲染的是**液态玻璃 tab 胶囊**：栏本身
/// 完全透明，只有胶囊采样背后的内容，页面标题不再占一行——四个 tab 的名字
/// 就是当前的栏目名。不在根壳层里（独立预览、推送页）退回原来的标题栏。
class FrostedTabHeader extends StatelessWidget {
  const FrostedTabHeader({
    super.key,
    required this.title,
    this.titleKey,
    this.leadingIcon,
    this.actions = const [],
    this.bottom,
    this.blur,
    this.vivid = true,
  });

  final String title;
  final Key? titleKey;
  final IconData? leadingIcon;
  final List<Widget> actions;
  final Widget? bottom;
  final double? blur;
  final bool vivid;

  /// Content height below the status bar.
  static const double barHeight = 72;
  static const double bottomPadding = 10;
  static const double _barBottomPadding = 12;

  static double extent(BuildContext context, {double extra = 0}) {
    return MediaQuery.paddingOf(context).top + barHeight + extra;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final tabs = RootTabScope.maybeOf(context);
    if (tabs != null) {
      // 右侧留一个固定宽度的槽位：设置页没有动作按钮时也占着位置，切 tab
      // 时胶囊宽度不会来回跳。
      final slots = actions.isEmpty ? 1 : actions.length;
      final surface = AppColors.scaffold(context);
      return Stack(
        children: [
          // 状态栏那一条只做中性渐隐：内容滚到时钟底下会糊成一片，
          // 但整条栏不铺毛玻璃——玻璃只留给胶囊。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top + 18,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.62, 1],
                    colors: [
                      surface,
                      surface.withValues(alpha: 0.86),
                      surface.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, top + 6, 12, _barBottomPadding),
            child: Row(
              children: [
                const Expanded(child: RootTabBar()),
                const SizedBox(width: 8),
                SizedBox(
                  width: slots * 44,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final action in actions)
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(child: action),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return _titleBar(context, top);
  }

  Widget _titleBar(BuildContext context, double top) {
    final accent = AppColors.accentOf(context);
    final isDark = AppColors.isDark(context);
    return GradientAppBarBackground(
      background: Theme.of(context).scaffoldBackgroundColor,
      blur: blur,
      vivid: vivid,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, top + 6, 14, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (leadingIcon != null) ...[
                    OrigoChromeSurface(
                      borderRadius: BorderRadius.circular(19),
                      padding: const EdgeInsets.all(10),
                      accent: accent,
                      emphasized: true,
                      child: Icon(leadingIcon, color: accent, size: 21),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      key: titleKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                        letterSpacing: -0.4,
                        color: AppColors.onScaffold(context),
                        shadows: [
                          Shadow(
                            color: AppColors.scaffold(
                              context,
                            ).withValues(alpha: isDark ? 0.62 : 0.42),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final action in actions) ...[
                    const SizedBox(width: 8),
                    action,
                  ],
                ],
              ),
            ),
            if (bottom != null) ...[const SizedBox(height: 6), bottom!],
          ],
        ),
      ),
    );
  }
}

class FrostedHeaderButton extends StatelessWidget {
  const FrostedHeaderButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.semanticLabel,
    this.dimmed = false,
    this.solid = false,
    this.iconSize = 20,
    this.padding = const EdgeInsets.all(8),
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  /// Unselected side-rail tabs keep the button visible, with a quieter icon.
  final bool dimmed;

  /// Opaque fill for the side rail. Glass there blurs the wrong surface
  /// and does not follow light and dark themes.
  final bool solid;
  final double iconSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.secondaryText(context);
    final iconWidget = Icon(
      icon,
      color: dimmed ? color.withValues(alpha: 0.38) : color,
      size: iconSize,
    );
    if (solid) {
      return Pressable(
        semanticLabel: semanticLabel,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.isDark(context)
                ? const Color(0x14FFFFFF)
                : const Color(0x14000000),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(padding: padding, child: iconWidget),
        ),
      );
    }
    // tab 胶囊旁边的按钮用同一块液态玻璃，避免一栏里出现两种材质。
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(19),
        blur: 18,
        opacity: 0.9,
        sheen: false,
        child: Padding(padding: padding, child: iconWidget),
      ),
    );
  }
}
