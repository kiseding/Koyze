import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'gradient_bar_backgrounds.dart';
import 'pressable.dart';

/// Shared large-title chrome for the four root tabs.
/// Frosted bar pinned to the status bar; list content should pad by [extent].
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

  static const double barHeight = 64;
  static const double bottomPadding = 10;

  static double extent(BuildContext context, {double extra = 0}) {
    return MediaQuery.paddingOf(context).top + barHeight + extra;
  }

  /// Equal side inset so the title stays centered and clear of the icon and actions.
  static double _titleSideInset(bool hasLeading, int actionCount) {
    final left = hasLeading ? 48.0 : 0.0;
    final right = actionCount * 44.0;
    return left > right ? left : right;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return GradientAppBarBackground(
      background: Theme.of(context).scaffoldBackgroundColor,
      blur: blur,
      vivid: vivid,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, top + 8, 10, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      if (leadingIcon != null) ...[
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.accentOf(
                              context,
                            ).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            leadingIcon,
                            color: AppColors.accentOf(context),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      const Spacer(),
                      for (final action in actions) ...[
                        const SizedBox(width: 4),
                        action,
                      ],
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: _titleSideInset(
                        leadingIcon != null,
                        actions.length,
                      ),
                    ),
                    child: Text(
                      title,
                      key: titleKey,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.1,
                        color: AppColors.onScaffold(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (bottom != null) ...[const SizedBox(height: 8), bottom!],
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
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: GlassSurface(
        style: AppGlassStyle.chrome,
        borderRadius: BorderRadius.circular(12),
        padding: padding,
        child: iconWidget,
      ),
    );
  }
}
