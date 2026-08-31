import 'package:flutter/material.dart';

/// Apple 现代设计规范色彩系统：纯黑/深灰阶梯层次，毛玻璃与微亮边
abstract final class AppColors {
  // Dark — OLED 纯黑与高质感层级
  static const Color bg = Color(0xFF000000);
  static const Color surface = Color(0x14FFFFFF); // 8%
  static const Color surface2 = Color(0x1FFFFFFF); // 12%
  static const Color border = Color(0x1FFFFFFF); // 12% 亮边

  static const Color amber = Color(0xFF34C759); // iOS System Green 主色
  static const Color amberDim = Color(0x3334C759);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xAAFFFFFF); // ~67%
  static const Color textMuted = Color(0x66FFFFFF); // 40%

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9F0A); // iOS System Orange
  static const Color error = Color(0xFFFF453A); // iOS system red
  static const Color info = Color(0xFF0A84FF); // iOS System Blue

  static const Color surfaceDark = Color(0xFF161618); // 更加深邃的二级背景
  static const Color surfaceVariant = Color(0xFF242426); // 三级高光背景

  // Light — iOS 浅色分层规范
  static const Color lightBg = Color(0xFFF2F2F7); // iOS grouped bg
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFE5E5EA);
  static const Color lightText = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0x993C3C43);
  static const Color lightTextMuted = Color(0x4D3C3C43);
  static const Color lightBorder = Color(0x18000000);
  static const Color lightAccent = Color(0xFF34C759);
  static const Color lightMiniBar = Color(0xE6FFFFFF); // 90% 毛玻璃底色
  static const Color lightSurfaceVariant = Color(0xFFE5E5EA);

  static bool isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color scaffold(BuildContext c) => isDark(c) ? bg : lightBg;
  static Color onScaffold(BuildContext c) =>
      isDark(c) ? textPrimary : lightText;
  static Color secondaryText(BuildContext c) =>
      isDark(c) ? textSecondary : lightTextSecondary;
  static Color mutedText(BuildContext c) =>
      isDark(c) ? textMuted : lightTextMuted;
  static Color card(BuildContext c) => isDark(c) ? surfaceDark : lightSurface;
  static Color cardAlt(BuildContext c) =>
      isDark(c) ? surfaceVariant : lightSurfaceVariant;
  static Color cardBorder(BuildContext c) => isDark(c) ? border : lightBorder;
  static Color fill(BuildContext c) =>
      isDark(c) ? surface : const Color(0x14787880);
  static Color fill2(BuildContext c) =>
      isDark(c) ? surface2 : const Color(0x24787880);
  static Color accentOf(BuildContext c) => Theme.of(c).colorScheme.primary;
  static Color miniBar(BuildContext c) =>
      isDark(c) ? const Color(0xE6161618) : lightMiniBar;
  static Color dialogBg(BuildContext c) =>
      isDark(c) ? surfaceDark : lightSurface;
}
