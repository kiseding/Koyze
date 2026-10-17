import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'gradient_bar_backgrounds.dart';
import 'pressable.dart';
import 'origo_chrome.dart';

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

  /// Content height below the status bar. A single title row, no eyebrow copy:
  /// the app name already appears on the hero card.
  static const double barHeight = 72;
  static const double bottomPadding = 10;

  static double extent(BuildContext context, {double extra = 0}) {
    return MediaQuery.paddingOf(context).top + barHeight + extra;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
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
                        // Keeps the title legible where artwork scrolls under
                        // the tapered frost. Cheaper than a solid panel.
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
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: OrigoChromeSurface(
        borderRadius: BorderRadius.circular(19),
        padding: padding,
        child: iconWidget,
      ),
    );
  }
}
