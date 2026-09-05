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
    this.subtitle,
    this.titleKey,
    this.leadingIcon,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Key? titleKey;
  final IconData? leadingIcon;
  final List<Widget> actions;
  final Widget? bottom;

  static const double barHeight = 64;
  static const double bottomPadding = 10;

  static double extent(
    BuildContext context, {
    double extra = 0,
  }) {
    return MediaQuery.paddingOf(context).top + barHeight + extra;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return GradientAppBarBackground(
      background: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, top + 8, 10, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  if (leadingIcon != null) ...[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentOf(context).withValues(alpha: 0.14),
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
                  Expanded(
                    child: subtitle == null
                        ? Text(
                            title,
                            key: titleKey,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.1,
                              color: AppColors.onScaffold(context),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                key: titleKey,
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
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.mutedText(context),
                                ),
                              ),
                            ],
                          ),
                  ),
                  for (final action in actions) ...[
                    const SizedBox(width: 4),
                    action,
                  ],
                ],
              ),
            ),
            if (bottom != null) ...[
              const SizedBox(height: 8),
              bottom!,
            ],
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
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: GlassSurface(
        style: AppGlassStyle.chrome,
        borderRadius: BorderRadius.circular(12),
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          color: AppColors.secondaryText(context),
          size: 20,
        ),
      ),
    );
  }
}
