import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
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

  static const double barHeight = 82;
  static const double bottomPadding = 12;

  static double extent(BuildContext context, {double extra = 0}) {
    return MediaQuery.paddingOf(context).top + barHeight + extra;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final accent = AppColors.accentOf(context);
    return GradientAppBarBackground(
      background: Theme.of(context).scaffoldBackgroundColor,
      blur: blur,
      vivid: vivid,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, top + 8, 12, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 58,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (leadingIcon != null) ...[
                    OrigoChromeSurface(
                      borderRadius: BorderRadius.circular(16),
                      padding: const EdgeInsets.all(10),
                      accent: accent,
                      child: Icon(leadingIcon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Koyze',
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.78),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          title,
                          key: titleKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: AppColors.onScaffold(context),
                            shadows: [
                              Shadow(
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor
                                    .withValues(alpha: 0.76),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final action in actions) ...[
                    const SizedBox(width: 8),
                    action,
                  ],
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
