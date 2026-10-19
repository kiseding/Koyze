// 文件说明：应用主题定义，照搬 origo-x：单一强调色生成完整 Material 3 色板。
// 技术要点：ColorScheme.fromSeed、强调色列表、深浅色板成对生成。

import 'package:flutter/material.dart';

/// origo-x 的取色方式：全应用只有一个强调色，浅/深两套色板都由它种子生成。
/// 这里不额外调色、不加自定义 surface，就是为了和 origo-x 的观感一致。
abstract final class AppThemes {
  /// origo-x 的默认强调色（Material Blue 700）。
  static const Color defaultAccentColor = Color(0xFF1976D2);

  /// 设置页中的快捷强调色。任意颜色仍可通过色盘或十六进制输入选择。
  static const List<Color> accentColors = [
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
    Color(0xFF2E7D32),
    Color(0xFF00897B),
    Color(0xFF0097A7),
    Color(0xFF0288D1),
    Color(0xFF5E6C84),
    Color(0xFF795548),
    Color(0xFFB26A00),
    Color(0xFF7D5260),
  ];

  static ColorScheme lightScheme(Color seedColor) =>
      ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light);

  static ColorScheme darkScheme(Color seedColor) =>
      ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);
}
