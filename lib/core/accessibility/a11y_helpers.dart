// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Accessibility support and WCAG compliance utilities.
/// 
/// Features:
/// - Semantic labels
/// - Screen reader support
/// - Keyboard navigation
/// - Focus management
/// - Contrast ratio checking
/// - Text scaling support

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Accessibility helper
class A11yHelper {
  /// Check if screen reader is enabled
  static bool isScreenReaderEnabled(BuildContext context) {
    return MediaQuery.of(context).accessibleNavigation;
  }

  /// Announce message to screen reader
  static void announce(BuildContext context, String message) {
    SemanticsService.announce(message, TextDirection.ltr);
  }

  /// Check color contrast ratio (WCAG AA requires 4.5:1 for normal text)
  static double calculateContrastRatio(Color foreground, Color background) {
    final fgLuminance = foreground.computeLuminance();
    final bgLuminance = background.computeLuminance();
    
    final lighter = fgLuminance > bgLuminance ? fgLuminance : bgLuminance;
    final darker = fgLuminance > bgLuminance ? bgLuminance : fgLuminance;
    
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Check if contrast meets WCAG AA standard (4.5:1)
  static bool meetsWCAG_AA(Color foreground, Color background) {
    return calculateContrastRatio(foreground, background) >= 4.5;
  }

  /// Check if contrast meets WCAG AAA standard (7:1)
  static bool meetsWCAG_AAA(Color foreground, Color background) {
    return calculateContrastRatio(foreground, background) >= 7.0;
  }

  /// Get accessible text size based on user preferences
  static double getAccessibleTextSize(BuildContext context, double baseSize) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    return baseSize * textScaleFactor.clamp(1.0, 2.0); // Max 2x scaling
  }
}

/// Accessible button with semantic labels
class AccessibleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final String? tooltip;

  const AccessibleButton({
    Key? key,
    required this.child,
    required this.semanticLabel,
    this.onPressed,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget button = FilledButton(
      onPressed: onPressed,
      child: child,
    );

    button = Semantics(
      label: semanticLabel,
      button: true,
      enabled: onPressed != null,
      child: ExcludeSemantics(child: button),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

/// Accessible icon button
class AccessibleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final String? tooltip;

  const AccessibleIconButton({
    Key? key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget button = IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
    );

    button = Semantics(
      label: semanticLabel,
      button: true,
      enabled: onPressed != null,
      child: ExcludeSemantics(child: button),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

/// Focus scope wrapper for keyboard navigation
class KeyboardNavigationScope extends StatefulWidget {
  final Widget child;
  final List<FocusNode>? focusNodes;

  const KeyboardNavigationScope({
    Key? key,
    required this.child,
    this.focusNodes,
  }) : super(key: key);

  @override
  State<KeyboardNavigationScope> createState() => _KeyboardNavigationScopeState();
}

class _KeyboardNavigationScopeState extends State<KeyboardNavigationScope> {
  final FocusScopeNode _focusScopeNode = FocusScopeNode();

  @override
  void dispose() {
    _focusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: _focusScopeNode,
      child: widget.child,
    );
  }
}

/// Accessible form field
class AccessibleTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String labelText;
  final String? hintText;
  final String? errorText;
  final String semanticLabel;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const AccessibleTextField({
    Key? key,
    this.controller,
    required this.labelText,
    required this.semanticLabel,
    this.hintText,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      textField: true,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          errorText: errorText,
        ),
      ),
    );
  }
}

/// Screen reader announcement widget
class ScreenReaderAnnouncement extends StatefulWidget {
  final String message;
  final Widget child;

  const ScreenReaderAnnouncement({
    Key? key,
    required this.message,
    required this.child,
  }) : super(key: key);

  @override
  State<ScreenReaderAnnouncement> createState() => _ScreenReaderAnnouncementState();
}

class _ScreenReaderAnnouncementState extends State<ScreenReaderAnnouncement> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      A11yHelper.announce(context, widget.message);
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Live region for dynamic content updates
class LiveRegion extends StatelessWidget {
  final Widget child;
  final String? liveRegionLabel;
  final bool assertive;

  const LiveRegion({
    Key? key,
    required this.child,
    this.liveRegionLabel,
    this.assertive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: liveRegionLabel,
      child: child,
    );
  }
}

/// Semantic music player controls
class AccessibleMusicPlayerControls extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final String currentSongTitle;

  const AccessibleMusicPlayerControls({
    Key? key,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.currentSongTitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '正在播放: $currentSongTitle',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AccessibleIconButton(
            icon: Icons.skip_previous,
            semanticLabel: '上一曲',
            tooltip: '播放上一曲',
            onPressed: onPrevious,
          ),
          SizedBox(width: 16),
          AccessibleIconButton(
            icon: isPlaying ? Icons.pause : Icons.play_arrow,
            semanticLabel: isPlaying ? '暂停' : '播放',
            tooltip: isPlaying ? '暂停播放' : '开始播放',
            onPressed: onPlayPause,
          ),
          SizedBox(width: 16),
          AccessibleIconButton(
            icon: Icons.skip_next,
            semanticLabel: '下一曲',
            tooltip: '播放下一曲',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// Accessible list item
class AccessibleListItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String semanticLabel;

  const AccessibleListItem({
    Key? key,
    required this.title,
    required this.semanticLabel,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

/// Focus trap for modal dialogs
class FocusTrap extends StatefulWidget {
  final Widget child;

  const FocusTrap({Key? key, required this.child}) : super(key: key);

  @override
  State<FocusTrap> createState() => _FocusTrapState();
}

class _FocusTrapState extends State<FocusTrap> {
  final FocusScopeNode _focusScopeNode = FocusScopeNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScopeNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: _focusScopeNode,
      child: widget.child,
    );
  }
}

/// WCAG contrast checker widget (debug only)
class ContrastChecker extends StatelessWidget {
  final Color foreground;
  final Color background;
  final Widget child;

  const ContrastChecker({
    Key? key,
    required this.foreground,
    required this.background,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    assert(() {
      final ratio = A11yHelper.calculateContrastRatio(foreground, background);
      final meetsAA = A11yHelper.meetsWCAG_AA(foreground, background);
      final meetsAAA = A11yHelper.meetsWCAG_AAA(foreground, background);
      
      debugPrint(
        '🎨 Contrast ratio: ${ratio.toStringAsFixed(2)}:1 '
        '(AA: ${meetsAA ? '✅' : '❌'}, AAA: ${meetsAAA ? '✅' : '❌'})'
      );
      
      return true;
    }());

    return child;
  }
}
