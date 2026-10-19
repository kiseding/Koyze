// 文件说明：毛玻璃效果配置，照搬 origo-x 的 GlassEffectConfig。
// 技术要点：模糊半径与透明度集中管理，性能模式下统一缩放。

import 'package:flutter/material.dart';

/// 毛玻璃参数集中管理。
///
/// origo-x 的做法是：所有悬浮 chrome（顶栏、悬浮导航、底部面板）共用同一组
/// 模糊与透明度，只在需要时整体缩放。这样任何一个玻璃面看起来都像同一块
/// 材质，而不是每个页面自己调一版。
abstract final class GlassEffectConfig {
  // ============ 模糊强度 (sigmaX/sigmaY) ============
  static const double _chromeBlurBase = 15.0;
  static const double _lightCardBlurBase = 8.0; // 轻量级容器（图标背景等）
  static const double _modalBlurBase = 25.0; // 底部弹出菜单
  // 全屏播放页背景：整块屏幕都糊，档位必须比面板高一档，否则封面上的字还
  // 能认出来，看着是「没模糊干净」而不是「设计」。
  static const double _playerBackdropBlurBase = 60.0;

  static double _blurScale = 0.85;
  static bool _reduceEffects = false;
  static bool _disableAllGlassEffects = false;

  static void applyPerformanceMode({required bool reduceEffects}) {
    _reduceEffects = reduceEffects;
    _syncBlurScale();
  }

  static void setDisableAllGlassEffects(bool disabled) {
    _disableAllGlassEffects = disabled;
    _syncBlurScale();
  }

  static void _syncBlurScale() {
    if (_disableAllGlassEffects) {
      _blurScale = 0.0;
      return;
    }
    _blurScale = _reduceEffects ? 0.65 : 0.85;
  }

  static double _scaled(double value) => value * _blurScale;

  static double get appBarBlur => _scaled(_chromeBlurBase);
  static double get navigationBarBlur => _scaled(_chromeBlurBase);
  static double get readingTopBarBlur => appBarBlur;
  static double get readingBottomBarBlur => navigationBarBlur;
  static double get lightCardBlur => _scaled(_lightCardBlurBase);
  static double get modalBlur => _scaled(_modalBlurBase);
  static double get playerBackdropBlur => _scaled(_playerBackdropBlurBase);

  // ============ 透明度 (alpha: 0.0-1.0) ============
  static const double _chromeOpacityBase = 0.3;
  static const double _lightChromeOpacityBase = 0.60;

  static double chromeOpacityFor(Brightness brightness) {
    return effectiveOpacity(
      brightness == Brightness.light
          ? _lightChromeOpacityBase
          : _chromeOpacityBase,
    );
  }

  /// 浅色下把底色往白里提亮，深色保持主题色本身。
  static Color chromeBaseColor(
    Color source,
    Brightness brightness, {
    double lightBlend = 0,
  }) {
    if (brightness == Brightness.light) {
      return Color.lerp(source, Colors.white, lightBlend.clamp(0.0, 1.0))!;
    }
    return source;
  }

  /// 玻璃共用底色：`surface` 朝 `primary` 轻染，所以换强调色时所有玻璃面
  /// 会一起变色，而不是留下一张固定的白卡。
  static Color chromeSurfaceColor(
    BuildContext context, {
    Color? source,
    Brightness? brightness,
    double? opacity,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedBrightness = brightness ?? scheme.brightness;
    final themedSource =
        source ??
        Color.lerp(
          scheme.surface,
          scheme.primary,
          resolvedBrightness == Brightness.light ? 0.08 : 0.06,
        )!;
    final base = chromeBaseColor(themedSource, resolvedBrightness);
    return base.withValues(
      alpha: effectiveOpacity(opacity ?? chromeOpacityFor(resolvedBrightness)),
    );
  }

  static bool get shouldDisableBlur => _disableAllGlassEffects;

  static double effectiveOpacity(double opacity) {
    if (_disableAllGlassEffects) return 1.0;
    return opacity.clamp(0.0, 1.0);
  }

  static Color surfaceColor(BuildContext context, {double opacity = 1.0}) {
    return Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: effectiveOpacity(opacity));
  }
}
