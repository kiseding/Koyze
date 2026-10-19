import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/core/theme/app_themes.dart';

void main() {
  group('AppTheme', () {
    test('darkTheme returns valid ThemeData', () {
      final theme = AppTheme.darkTheme();
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, true);
    });

    test('darkTheme has correct scaffold background', () {
      final theme = AppTheme.darkTheme();
      expect(theme.scaffoldBackgroundColor, AppColors.bg);
    });

    test('darkTheme primary is the accent, lifted for a dark surface', () {
      final theme = AppTheme.darkTheme();
      expect(
        theme.colorScheme.primary,
        AppThemes.keyColor(
          AppThemes.defaultAccentColor,
          isDark: true,
        ),
      );
    });

    test('changing the accent leaves page surfaces neutral', () {
      final blue = AppTheme.lightTheme();
      final magenta = AppTheme.lightTheme(
        seedColor: const Color(0xFFD81B60),
      );

      expect(magenta.scaffoldBackgroundColor, blue.scaffoldBackgroundColor);
      expect(magenta.colorScheme.surface, blue.colorScheme.surface);
      expect(
        magenta.colorScheme.surfaceContainer,
        blue.colorScheme.surfaceContainer,
      );
      expect(magenta.colorScheme.outlineVariant, blue.colorScheme.outlineVariant);
      // 只有 primary 这一路跟着强调色走。
      expect(magenta.colorScheme.primary, isNot(blue.colorScheme.primary));
    });

    test('light input fields keep a visible edge on white surfaces', () {
      final theme = AppTheme.lightTheme();
      final input = theme.inputDecorationTheme;
      expect(input.filled, isTrue);
      expect(input.fillColor, isNot(AppColors.lightSurface));
      final border = input.enabledBorder ?? input.border;
      expect(border, isA<OutlineInputBorder>());
      final side = (border as OutlineInputBorder).borderSide;
      expect(side.style, isNot(BorderStyle.none));
      expect(side.color.a, greaterThan(0));
    });

    test('默认强调色是一支绿，且排在色板第一格', () {
      final hsl = HSLColor.fromColor(AppThemes.defaultAccentColor);
      expect(hsl.hue, inInclusiveRange(90, 150));
      expect(hsl.saturation, greaterThan(0.3));

      // 色板第一格就是默认值：选中态才不会落在一块看起来"随机"的色板上。
      expect(AppThemes.accentColors.first, AppThemes.defaultAccentColor);
      expect(
        AppThemes.accentColors.toSet().length,
        AppThemes.accentColors.length,
      );
    });
  });
}
