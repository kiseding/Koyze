// 文件说明：应用主题定义。
// 技术要点：中性种子生成 M3 结构色板，强调色原样挂在 primary 上，
// 页面底色 / 卡片 / 描边 / 文字全部锁定为中性灰阶——换主题色时只有
// 关键元素（选中 tab、播放键、开关、主按钮、大卡片）跟着变。

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 主题构建入口。
///
/// 之前是「一个种子色生成整套色板」，结果换个蓝/绿/紫，页面底色、卡片、
/// 分隔线全跟着偏色，看起来像整屏被染过。这里把两件事拆开：
/// - 结构色（surface / container / outline / 文字）来自固定中性种子，
///   因此任何强调色下页面都是同一张灰阶；
/// - `primary` 就是用户选的那支颜色本身，只落在关键元素上。
abstract final class AppThemes {
  /// origo-x 的默认强调色：v3.0.7 那支绿（#1DB954）。
  static const Color defaultAccentColor = Color(0xFF1DB954);

  /// 设置页中的快捷强调色。任意颜色仍可通过色盘或十六进制输入选择。
  /// 默认色排在第一格，选中态才不会落在一块看起来"随机"的色板上。
  static const List<Color> accentColors = [
    Color(0xFF1DB954),
    Color(0xFF1976D2),
    Color(0xFF3F51B5),
    Color(0xFF6750A4),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
    Color(0xFFE53935),
    Color(0xFFF4511E),
    Color(0xFFFB8C00),
    Color(0xFFF9A825),
    Color(0xFF7CB342),
    Color(0xFF00897B),
    Color(0xFF0097A7),
    Color(0xFF0288D1),
    Color(0xFF5E6C84),
    Color(0xFF795548),
    Color(0xFFB26A00),
    Color(0xFF7D5260),
  ];

  /// 只负责「结构」的种子：明度阶梯是灰的，色彩由 [primary] 单独给。
  static const Color _neutralSeed = Color(0xFF5C5F62);

  static ColorScheme lightScheme(Color accent) =>
      _scheme(accent, Brightness.light);

  static ColorScheme darkScheme(Color accent) =>
      _scheme(accent, Brightness.dark);

  static ColorScheme _scheme(Color accent, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: _neutralSeed,
      brightness: brightness,
    );
    return base.copyWith(
      // 用户选的是哪支颜色，主色就是哪支颜色。
      //
      // 这里以前会把强调色按亮度"抬"到可读区间（深色下提到 0.66 明度、
      // 浅色下压到 0.42），结果是设置里点了一格深蓝，界面上的选中态、
      // 播放键却是另一支亮蓝，看起来像没生效。色调与明度都不再改写，
      // 只在 onPrimary 上做对比度兜底，保证压在色块上的图标仍看得清。
      primary: accent,
      onPrimary: onAccentColor(accent),
      primaryContainer: isDark
          ? Color.alphaBlend(
              accent.withValues(alpha: 0.24),
              AppColors.surfaceDark,
            )
          : Color.alphaBlend(accent.withValues(alpha: 0.14), Colors.white),
      onPrimaryContainer: isDark ? AppColors.textPrimary : AppColors.lightText,
      secondary: isDark
          ? AppColors.textSecondary
          : AppColors.lightTextSecondary,
      onSecondary: isDark ? AppColors.bg : Colors.white,
      surface: isDark ? AppColors.bg : AppColors.lightBg,
      onSurface: isDark ? AppColors.textPrimary : AppColors.lightText,
      onSurfaceVariant: isDark
          ? AppColors.textSecondary
          : AppColors.lightTextSecondary,
      surfaceContainerLowest: isDark ? const Color(0xFF0C0E12) : Colors.white,
      surfaceContainerLow: isDark
          ? const Color(0xFF181A1F)
          : AppColors.lightSurface2,
      surfaceContainer: isDark
          ? AppColors.surfaceDark
          : const Color(0xFFEDEDF4),
      surfaceContainerHigh: isDark
          ? AppColors.surfaceVariant
          : AppColors.lightSurfaceVariant,
      surfaceContainerHighest: isDark
          ? const Color(0xFF31343A)
          : const Color(0xFFE2E3EA),
      outline: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
      outlineVariant: isDark ? AppColors.border : AppColors.lightBorder,
      surfaceTint: Colors.transparent,
      error: AppColors.error,
      onError: Colors.white,
    );
  }

  /// 压在强调色上的文字/图标色。
  ///
  /// 强调色不再按明暗改写，所以对比度只能在这里补：亮底配黑字、暗底配白字，
  /// 用户挑的土黄、亮橙当主色时，播放键上的图标也不会糊成一片。
  static Color onAccentColor(Color accent) {
    return ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }
}
