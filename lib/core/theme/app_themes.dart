// 文件说明：应用主题定义。
// 技术要点：中性种子生成 M3 结构色板，强调色只挂在 primary 上，
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
/// - `primary` 直接取强调色（深色下按亮度提亮），只落在关键元素上。
abstract final class AppThemes {
  /// origo-x 的默认强调色（Material Green 800）。
  ///
  /// 暖色在深色底上会发灰，蓝紫又太像系统控件；这支深绿在浅色下是
  /// 5.2:1 的实心绿，深色下经 [keyColor] 提到 0.66 明度后变成一枚
  /// 干净的浅绿，两个主题都是同一支色相。
  static const Color defaultAccentColor = Color(0xFF2E7D32);

  /// 设置页中的快捷强调色。任意颜色仍可通过色盘或十六进制输入选择。
  /// 默认色排在第一格，选中态才不会落在一块看起来"随机"的色板上。
  static const List<Color> accentColors = [
    Color(0xFF2E7D32),
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
    final key = keyColor(accent, isDark: isDark);
    return base.copyWith(
      primary: key,
      onPrimary: onKeyColor(key),
      primaryContainer: isDark
          ? Color.alphaBlend(key.withValues(alpha: 0.24), AppColors.surfaceDark)
          : Color.alphaBlend(key.withValues(alpha: 0.14), Colors.white),
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

  /// 强调色本身的显示值。
  ///
  /// 深色页面上一支 0x1976D2 的深蓝几乎看不见，直接压到图标上会糊成一团；
  /// 浅色页面上一支亮黄又会让文字失去对比。这里只调明度，不动色相——
  /// 用户选的还是那个颜色，只是落到可读区间。
  static Color keyColor(Color accent, {required bool isDark}) {
    final hsl = HSLColor.fromColor(accent);
    if (isDark) {
      if (hsl.lightness >= 0.60) return accent;
      return hsl
          .withLightness(0.66)
          .withSaturation(hsl.saturation.clamp(0.30, 1.0))
          .toColor();
    }
    if (hsl.lightness <= 0.46) return accent;
    return hsl
        .withLightness(0.42)
        .withSaturation(hsl.saturation.clamp(0.30, 1.0))
        .toColor();
  }

  /// 压在强调色上的文字/图标色。
  static Color onKeyColor(Color key) {
    return ThemeData.estimateBrightnessForColor(key) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }
}
