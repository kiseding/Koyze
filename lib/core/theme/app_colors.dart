import 'package:flutter/material.dart';

/// 主题色板。
///
/// 结构性颜色（页面底、卡片、描边、文字）是固定的中性灰阶，不随主题色变化：
/// 换一支强调色时页面不应该整体发蓝或发绿，只有关键元素跟着变。
/// 强调色本身请用 [accentOf]（读 `colorScheme.primary`），不要再新增静态常量。
abstract final class AppColors {
  // ---------------- 深色 =================
  /// ColorScheme.surface
  static const Color bg = Color(0xFF111318);

  /// ColorScheme.surfaceContainer（卡片 / 对话框底色）
  static const Color surfaceDark = Color(0xFF1D2024);

  /// ColorScheme.surfaceContainerHigh
  static const Color surfaceVariant = Color(0xFF282A2F);

  /// 8% 白色填充，压在深色底上的轻量面
  static const Color surface = Color(0x14FFFFFF);

  /// 12% 白色填充
  static const Color surface2 = Color(0x1FFFFFFF);

  /// outlineVariant：M3 的卡片描边 / 分隔线
  static const Color border = Color(0xFF43474E);

  /// ColorScheme.onSurface
  static const Color textPrimary = Color(0xFFE1E2E9);

  /// ColorScheme.onSurfaceVariant
  static const Color textSecondary = Color(0xFFC3C6CF);

  /// outline：第三层信息
  static const Color textMuted = Color(0xFF8D9199);

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  // 语义色不参与种子生成：红/绿/橙在深浅两个主题里都要一眼认出。
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color error = Color(0xFFFF453A); // iOS system red
  static const Color info = Color(0xFF0A84FF);

  // ---------------- 浅色 =================
  /// ColorScheme.surface（浅色）
  static const Color lightBg = Color(0xFFF9F9FF);
  static const Color lightSurface = Color(0xFFFFFFFF); // surfaceContainerLowest
  static const Color lightSurface2 = Color(0xFFF3F3FA); // surfaceContainerLow
  static const Color lightSurfaceVariant = Color(0xFFE7E8EE);
  static const Color lightBorder = Color(0xFFC3C6CF); // outlineVariant

  /// ColorScheme.onSurface（浅色）
  static const Color lightText = Color(0xFF191C20);
  static const Color lightTextSecondary = Color(0xFF43474E);
  static const Color lightTextMuted = Color(0xFF74777F); // outline

  static const Color lightMiniBar = Color(0xF2FFFFFF);

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
      isDark(c) ? surface2 : const Color(0x29787880);
  static Color accentOf(BuildContext c) => Theme.of(c).colorScheme.primary;
  static Color onAccentOf(BuildContext c) => Theme.of(c).colorScheme.onPrimary;
  static Color miniBar(BuildContext c) =>
      isDark(c) ? const Color(0xF21D2024) : lightMiniBar;
  static Color dialogBg(BuildContext c) =>
      isDark(c) ? surfaceDark : lightSurface;
}
