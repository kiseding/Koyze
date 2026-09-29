// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:math' as math;
/// Optimized player UI with modern layout and smooth animations.
/// 
/// Features:
/// - Full-screen player layout
/// - Mini player bar
/// - Album art with blur background
/// - Smooth controls
/// - Lyrics display
/// - Queue management

import 'package:flutter/material.dart';
import 'dart:ui';
import '../ui/responsive_layout.dart';
import '../ui/animations.dart';

/// Full-screen music player
class FullScreenPlayer extends StatelessWidget {
  final String songTitle;
  final String artistName;
  final String? albumName;
  final String? coverUrl;
  final bool isPlaying;
  final Duration currentPosition;
  final Duration totalDuration;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onClose;

  const FullScreenPlayer({
    Key? key,
    required this.songTitle,
    required this.artistName,
    this.albumName,
    this.coverUrl,
    required this.isPlaying,
    required this.currentPosition,
    required this.totalDuration,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    this.onSeek,
    this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.keyboard_arrow_down),
          onPressed: onClose ?? () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Stack(
        children: [
          // Blurred background
          if (coverUrl != null)
            Positioned.fill(
              child: Image.network(
                coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Blur overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                color: theme.colorScheme.surface.withOpacity(0.7),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: ResponsiveBody(
              centerContent: true,
              child: Column(
                children: [
                  Spacer(),

                  // Album art
                  _buildAlbumArt(context, size),

                  SizedBox(height: LayoutSpacing.xl),

                  // Song info
                  _buildSongInfo(context),

                  SizedBox(height: LayoutSpacing.xl),

                  // Progress bar
                  _buildProgressBar(context),

                  SizedBox(height: LayoutSpacing.lg),

                  // Controls
                  _buildControls(context),

                  Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(BuildContext context, Size size) {
    final config = LayoutConfig.fromContext(context);
    final artSize = config.isMobile 
        ? size.width * 0.75 
        : math.min(size.width * 0.4, 400.0);

    return Hero(
      tag: 'album_art_$songTitle',
      child: Container(
        width: artSize,
        height: artSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 30,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: coverUrl != null
              ? Image.network(
                  coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPlaceholder(),
                )
              : _buildPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: Icon(
        Icons.music_note,
        size: 120,
        color: Colors.white.withOpacity(0.5),
      ),
    );
  }

  Widget _buildSongInfo(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: LayoutSpacing.lg),
      child: Column(
        children: [
          Text(
            songTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: LayoutSpacing.sm),
          Text(
            albumName != null ? '$artistName · $albumName' : artistName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final theme = Theme.of(context);
    final progress = totalDuration.inSeconds > 0
        ? currentPosition.inSeconds / totalDuration.inSeconds
        : 0.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: LayoutSpacing.lg),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: onSeek != null
                  ? (value) {
                      final position = totalDuration.inSeconds * value;
                      onSeek!(position);
                    }
                  : null,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: LayoutSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(currentPosition),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  _formatDuration(totalDuration),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: LayoutSpacing.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Previous
          IconButton(
            icon: Icon(Icons.skip_previous, size: 40),
            onPressed: onPrevious,
            color: theme.colorScheme.onSurface,
          ),

          // Play/Pause
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.4),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                size: 36,
              ),
              onPressed: onPlayPause,
              color: theme.colorScheme.onPrimary,
            ),
          ),

          // Next
          IconButton(
            icon: Icon(Icons.skip_next, size: 40),
            onPressed: onNext,
            color: theme.colorScheme.onSurface,
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Mini player bar
class MiniPlayerBar extends StatelessWidget {
  final String songTitle;
  final String artistName;
  final String? coverUrl;
  final bool isPlaying;
  final double progress;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  const MiniPlayerBar({
    Key? key,
    required this.songTitle,
    required this.artistName,
    this.coverUrl,
    required this.isPlaying,
    required this.progress,
    required this.onTap,
    required this.onPlayPause,
    required this.onNext,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        margin: EdgeInsets.all(LayoutSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Progress indicator
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),

            // Content
            Padding(
              padding: EdgeInsets.symmetric(horizontal: LayoutSpacing.sm),
              child: Row(
                children: [
                  // Cover
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: coverUrl != null
                          ? Image.network(
                              coverUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildPlaceholder(),
                            )
                          : _buildPlaceholder(),
                    ),
                  ),

                  SizedBox(width: LayoutSpacing.md),

                  // Song info
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          songTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Controls
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: onPlayPause,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),

                  SizedBox(width: LayoutSpacing.sm),

                  IconButton(
                    icon: Icon(Icons.skip_next),
                    onPressed: onNext,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Icon(
        Icons.music_note,
        size: 24,
        color: Colors.grey[600],
      ),
    );
  }
}
