// 文件说明：毛玻璃效果配置，照搬 origo-x 的 GlassEffectConfig。
// 技术要点：模糊半径与透明度集中管理，性能模式下统一缩放。

import 'package:flutter/foundation.dart';
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
  static double _surfaceOpacity = defaultSurfaceOpacity;

  /// 设置页暴露的「界面不透明度」下限。
  ///
  /// 再往下玻璃就只剩一条边，列表文字会直接压在下面的内容上；0.3 是还能
  /// 认出「这里有一块面板」的最后一档。
  static const double minSurfaceOpacity = 0.3;

  /// 「界面不透明度」的默认档。
  ///
  /// 只是出厂值，不参与任何换算——见 [surfaceAlpha]。0.95 是「几乎实色、
  /// 但仍留一点透光」的档位：再往上玻璃就只剩材质感没有背景色了，而早先
  /// 的 0.8 在深色主题下会让顶栏和卡片透出底下的滚动内容，看着发灰。
  static const double defaultSurfaceOpacity = 0.95;

  static void applyPerformanceMode({required bool reduceEffects}) {
    _reduceEffects = reduceEffects;
    _syncBlurScale();
  }

  /// 透明度变了会通知这里。
  ///
  /// 光改一个静态字段不会让已经建好的界面重画——设置页滑杆在动，但顶栏、
  /// 卡片、迷你播放条都还停在旧的一帧，看起来就是「拖了没反应」。玻璃面
  /// 各自监听这个信号，改完当帧重画自己，不必等外层重建。
  static final ValueNotifier<double> _surfaceOpacitySignal =
      ValueNotifier<double>(defaultSurfaceOpacity);

  static ValueListenable<double> get surfaceOpacityListenable =>
      _surfaceOpacitySignal;

  /// 全局材质不透明度（0.3~1）。0.95 是出厂默认，1 是完全实色。
  static void setSurfaceOpacity(double value) {
    final next = value.isFinite
        ? value.clamp(minSurfaceOpacity, 1.0).toDouble()
        : defaultSurfaceOpacity;
    if (next == _surfaceOpacity) return;
    _surfaceOpacity = next;
    _surfaceOpacitySignal.value = next;
  }

  static double get surfaceOpacity => _surfaceOpacity;

  /// 此刻真正画到玻璃上的 alpha——**就是设置里选的那个百分比**。
  ///
  /// 这里不做任何曲线换算。早先为了让「背后糊过就更淡、没糊就更浓」的相对
  /// 关系成立，把档位映射成两段：默认档以下按比例减淡，以上朝 1.0 补齐。
  /// 代价是同一个 80%，顶栏显示成 0.30、卡片 0.82、菜单 0.64，滑杆上的数字
  /// 和眼睛看到的永远对不上。
  ///
  /// 现在档位即最终值：选 50% 就是半透明，选 100% 就是实色，所见即所得。
  /// 各材质之间不再有浓度差，需要更淡就把滑杆往左拖。
  static double get surfaceAlpha =>
      _disableAllGlassEffects ? 1.0 : _surfaceOpacity;

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

  /// 把用户设定的背景模糊档位换算成生效 sigma。
  ///
  /// 设置页里存的是「用户档位」（0~100），不是生效值；性能模式与「关闭玻璃
  /// 效果」仍然在它之上缩放，所以同一个档位在简化动效下会更轻。
  static double playerBackdropBlurFor(double userValue) => _scaled(userValue);

  /// 全屏播放器背景的可读性罩层。
  ///
  /// 封面在强模糊后仍可能出现整片高亮或深色区域；只靠普通玻璃透明度
  /// 会让这些区域与前景文字/图标撞色。使用主题方向相反的中性罩层，保留
  /// 少量封面色相，同时把背景亮度稳定在前景内容可读的范围内。
  ///
  /// [opacity] 是设置页暴露的那一档（0~1，默认 0.8 即原先写死的 `0xCC`）。
  static Color playerBackdropScrimFor(
    Brightness brightness, {
    double opacity = 0.8,
  }) {
    final alpha = (effectiveOpacity(opacity) * 255).round();
    return brightness == Brightness.dark
        ? Color.fromARGB(alpha, 0, 0, 0)
        : Color.fromARGB(alpha, 255, 255, 255);
  }

  // ============ 透明度 (alpha: 0.0-1.0) ============
  //
  // 只有一档浓度：设置里选的那个百分比，见 [surfaceAlpha]。原先按「背后糊
  // 没糊」分 0.30/0.60 与 0.66/0.82 两套基础浓度，再乘用户档位；同一个数字
  // 落在不同材质上会显示成四种深浅，滑杆因此失去了意义。

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
    return base.withValues(alpha: effectiveOpacity(opacity ?? surfaceAlpha));
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
