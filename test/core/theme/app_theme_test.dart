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

    test('primary 就是设置里选的那支颜色，深浅色都不改写', () {
      for (final accent in AppThemes.accentColors) {
        expect(
          AppTheme.darkTheme(seedColor: accent).colorScheme.primary,
          accent,
        );
        expect(
          AppTheme.lightTheme(seedColor: accent).colorScheme.primary,
          accent,
        );
      }
    });

    test('onPrimary 跟着强调色明暗走，压在色块上的图标仍然看得清', () {
      final indigo = AppTheme.lightTheme(seedColor: const Color(0xFF3F51B5));
      expect(indigo.colorScheme.onPrimary, Colors.white);

      final amber = AppTheme.lightTheme(seedColor: const Color(0xFFF9A825));
      expect(amber.colorScheme.onPrimary, Colors.black);
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
