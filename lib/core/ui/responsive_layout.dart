// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Modern responsive layout system with adaptive spacing and breakpoints.
/// 
/// Features:
/// - Responsive breakpoints (mobile/tablet/desktop)
/// - Adaptive spacing system
/// - Grid layout utilities
/// - Card layouts
/// - Safe area handling
/// - Platform-specific optimizations

import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Responsive breakpoints
class LayoutBreakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1600;
}

/// Spacing scale following 8dp grid
class LayoutSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;
}

/// Layout configuration based on screen size
class LayoutConfig {
  final double width;
  final double height;
  final bool isMobile;
  final bool isTablet;
  final bool isDesktop;
  final int gridColumns;
  final double contentMaxWidth;
  final EdgeInsets pagePadding;

  const LayoutConfig({
    required this.width,
    required this.height,
    required this.isMobile,
    required this.isTablet,
    required this.isDesktop,
    required this.gridColumns,
    required this.contentMaxWidth,
    required this.pagePadding,
  });

  factory LayoutConfig.fromConstraints(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;

    final isMobile = width < LayoutBreakpoints.mobile;
    final isTablet = width >= LayoutBreakpoints.mobile && 
                      width < LayoutBreakpoints.desktop;
    final isDesktop = width >= LayoutBreakpoints.desktop;

    final gridColumns = isMobile ? 2 : (isTablet ? 3 : 4);
    final contentMaxWidth = math.min(width * 0.9, 1200.0);
    
    final pagePadding = EdgeInsets.symmetric(
      horizontal: isMobile ? LayoutSpacing.md : LayoutSpacing.lg,
      vertical: isMobile ? LayoutSpacing.sm : LayoutSpacing.md,
    );

    return LayoutConfig(
      width: width,
      height: height,
      isMobile: isMobile,
      isTablet: isTablet,
      isDesktop: isDesktop,
      gridColumns: gridColumns,
      contentMaxWidth: contentMaxWidth,
      pagePadding: pagePadding,
    );
  }

  factory LayoutConfig.fromContext(BuildContext context) {
    return LayoutConfig.fromConstraints(
      BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
        maxHeight: MediaQuery.of(context).size.height,
      ),
    );
  }
}

/// Responsive layout wrapper
class ResponsiveLayout extends StatelessWidget {
  final Widget Function(BuildContext, LayoutConfig) builder;

  const ResponsiveLayout({
    Key? key,
    required this.builder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final config = LayoutConfig.fromConstraints(constraints);
        return builder(context, config);
      },
    );
  }
}

/// Adaptive scaffold with responsive layout
class AdaptiveScaffold extends StatelessWidget {
  final String? title;
  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final bool centerTitle;
  final bool extendBodyBehindAppBar;
  final PreferredSizeWidget? bottom;

  const AdaptiveScaffold({
    Key? key,
    this.title,
    required this.body,
    this.floatingActionButton,
    this.actions,
    this.bottomNavigationBar,
    this.centerTitle = false,
    this.extendBodyBehindAppBar = false,
    this.bottom,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final config = LayoutConfig.fromContext(context);

    return Scaffold(
      appBar: title != null
          ? AppBar(
              title: Text(title!),
              centerTitle: centerTitle || config.isMobile,
              actions: actions,
              bottom: bottom,
              elevation: 0,
            )
          : null,
      body: SafeArea(
        child: ResponsiveBody(
          child: body,
        ),
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
    );
  }
}

/// Responsive body with max width constraint
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final bool centerContent;

  const ResponsiveBody({
    Key? key,
    required this.child,
    this.centerContent = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      builder: (context, config) {
        if (config.isDesktop && centerContent) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: config.contentMaxWidth,
              ),
              child: child,
            ),
          );
        }

        return Padding(
          padding: config.pagePadding,
          child: child,
        );
      },
    );
  }
}

/// Adaptive grid for music/album cards
class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double childAspectRatio;
  final double spacing;

  const AdaptiveGrid({
    Key? key,
    required this.children,
    this.childAspectRatio = 1.0,
    this.spacing = LayoutSpacing.md,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      builder: (context, config) {
        return GridView.count(
          crossAxisCount: config.gridColumns,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          children: children,
        );
      },
    );
  }
}

/// Modern card with elevation and rounded corners
class ModernCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final double elevation;
  final double borderRadius;

  const ModernCard({
    Key? key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.color,
    this.elevation = 0,
    this.borderRadius = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: elevation * 2,
                  offset: Offset(0, elevation),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(LayoutSpacing.md),
        child: child,
      ),
    );

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: card,
      );
    }

    return card;
  }
}

/// Album/Song card with cover image
class MusicCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final Widget? trailing;

  const MusicCard({
    Key? key,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.onTap,
    this.onPlay,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ModernCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover image
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                // Image
                ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),

                // Play button overlay
                if (onPlay != null)
                  Positioned(
                    bottom: LayoutSpacing.sm,
                    right: LayoutSpacing.sm,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.play_arrow,
                          color: theme.colorScheme.onPrimary,
                        ),
                        onPressed: onPlay,
                        padding: EdgeInsets.all(LayoutSpacing.sm),
                        constraints: BoxConstraints(),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Title and subtitle
          Padding(
            padding: EdgeInsets.all(LayoutSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Trailing widget
          if (trailing != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: LayoutSpacing.sm),
              child: trailing,
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 48,
          color: Colors.grey[400],
        ),
      ),
    );
  }
}

/// Song list item with optimized layout
class OptimizedSongListItem extends StatelessWidget {
  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final Duration? duration;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final Widget? trailing;
  final bool isPlaying;

  const OptimizedSongListItem({
    Key? key,
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    this.duration,
    this.onTap,
    this.onPlay,
    this.trailing,
    this.isPlaying = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: LayoutSpacing.md,
          vertical: LayoutSpacing.sm,
        ),
        child: Row(
          children: [
            // Cover image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: coverUrl != null
                    ? Image.network(
                        coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildCoverPlaceholder(),
                      )
                    : _buildCoverPlaceholder(),
              ),
            ),

            SizedBox(width: LayoutSpacing.md),

            // Title, artist, album
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isPlaying ? theme.colorScheme.primary : null,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    album != null ? '$artist · $album' : artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Duration
            if (duration != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: LayoutSpacing.sm),
                child: Text(
                  _formatDuration(duration!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            // Trailing action
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        Icons.music_note,
        size: 24,
        color: Colors.grey[400],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Section header with title and optional action
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets? padding;

  const SectionHeader({
    Key? key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: LayoutSpacing.md,
            vertical: LayoutSpacing.sm,
          ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
