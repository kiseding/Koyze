import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'gradient_bar_backgrounds.dart';
import 'liquid_glass.dart';
import 'pressable.dart';
import 'root_tab_bar.dart';
import 'origo_chrome.dart';

/// 根页面的顶部 chrome。
///
/// 在根壳层里（存在 [RootTabScope]）它只有一行：图标 tab（[RootTabBar]）
/// 占住原来标题的位置，动作按钮留在右侧。选中的那一项展开后本身就是这一页
/// 的名字，不必再写一遍大标题。不在根壳层里（独立预览、推送页）退回原来的
/// 标题栏。
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

  /// 根壳层里的状态栏以下高度：一条导航行。
  static const double barHeight = _topPadding + _navRowHeight + _bottomPadding;

  /// 回退标题栏（推送页、独立预览）的状态栏以下高度。
  static const double _plainBarHeight = 72;

  static const double _topPadding = 6;
  static const double _navRowHeight = 46;
  static const double _bottomPadding = 8;

  static const double bottomPadding = 10;

  static double extent(BuildContext context, {double extra = 0}) {
    // 有 tab 条的壳层比回退标题栏高一条 tab 的高度，滚动留白必须跟着走，
    // 否则列表会从图标底下钻出来。
    final hasTabs = RootTabScope.readOf(context) != null;
    return MediaQuery.paddingOf(context).top +
        (hasTabs ? barHeight : _plainBarHeight) +
        extra;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final tabs = RootTabScope.maybeOf(context);
    if (tabs != null) {
      final surface = AppColors.scaffold(context);
      return Stack(
        children: [
          // 导航行需要一层底：列表滚上来时是从图标和药丸背后穿过的，
          // 没有这层渐隐，文字会和歌词/歌名糊在一起。整块 chrome 高度上
          // 保持实心，只在最后一段淡出——半透明会把封面上的亮色漏到
          // 图标之间，看着像栏「脏了」。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top + barHeight + 28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.82, 1],
                    colors: [
                      surface,
                      surface,
                      surface.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + _topPadding, 12, _bottomPadding),
            child: SizedBox(
              height: _navRowHeight,
              // 标题不再画出来，但定位锚点还得有落点：首页搜索弹窗用这个
              // key 量顶部留白。挂在导航行上，量到的仍是整条栏的位置。
              child: KeyedSubtree(
                key: titleKey,
                child: Row(
                  children: [
                    // tab 条从左起排。展开项会让整条变宽，窄屏上等比缩一下，
                    // 比让 Row 溢出好看。
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: RootTabBar(),
                        ),
                      ),
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      for (final action in actions)
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(child: action),
                        ),
                    ],
                  ],
                ),
              ),
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
