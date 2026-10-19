import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_themes.dart';

/// 主题构建，照搬 origo-x：一个种子色 + Material 3 默认组件外观。
///
/// origo-x 的 `ThemeData` 里只有 `colorSchemeSeed` / `brightness` / `useMaterial3`
/// 三项，其余全部交给 M3 的默认值。这里保留同样的结构，只补上三类必须显式
/// 指定的东西：
/// - 页面底色用 `colorScheme.surface`，避免 Material 默认的浅紫偏色；
/// - 状态栏图标随明暗切换；
/// - 输入框聚焦不套强调色描边（强调色描边会让搜索、重命名这类浮层同时亮圈）。
abstract final class AppTheme {
  static ThemeData darkTheme({Color seedColor = AppThemes.defaultAccentColor}) =>
      _build(seedColor, Brightness.dark);

  static ThemeData lightTheme({
    Color seedColor = AppThemes.defaultAccentColor,
  }) => _build(seedColor, Brightness.light);

  static ThemeData _build(Color seedColor, Brightness brightness) {
    final scheme = brightness == Brightness.dark
        ? AppThemes.darkScheme(seedColor)
        : AppThemes.lightScheme(seedColor);
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    final isDark = brightness == Brightness.dark;
    final radius = BorderRadius.circular(12);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant, width: 0.6),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: scheme.outlineVariant, width: 0.6),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: scheme.onSurface),
        position: PopupMenuPosition.under,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        // 聚焦只用中性色描边：主题级强调色描边会在搜索面板、重命名、
        // 自定义音源这些浮层输入框上同时亮成一圈，很刺眼。
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outline, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: Colors.transparent,
        dividerHeight: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
    );
  }
}
