// 文件说明：毛玻璃效果配置，照搬 origo-x 的 GlassEffectConfig。
// 技术要点：模糊半径与透明度集中管理，性能模式下统一缩放。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/liquid_glass_filter.dart';

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
  static double _surfaceBlur = defaultSurfaceBlur;

  /// 设置页暴露的「界面不透明度」下限。
  static const double minSurfaceOpacity = 0.0;

  /// 「界面不透明度」的默认档。0 表示不额外叠加染色底色，由虚化和边线建立
  /// 面板轮廓；用户仍可在设置里提高不透明度以适配不同背景和阅读习惯。
  static const double defaultSurfaceOpacity = 0.0;

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

  /// 全局材质不透明度（0.3~1）。0.65 是出厂默认，1 是完全实色。
  ///
  /// 非法值（NaN / Infinity）退回上限 1.0 而不是出厂档：坏数据只该让材质变成
  /// 最保守的实色，不该让它变透——透出来的东西压着文字是最难读的状态。
  static void setSurfaceOpacity(double value) {
    final next = value.isFinite
        ? value.clamp(minSurfaceOpacity, 1.0).toDouble()
        : 1.0;
    if (next == _surfaceOpacity) return;
    _surfaceOpacity = next;
    _surfaceOpacitySignal.value = next;
  }

  static double get surfaceOpacity => _surfaceOpacity;

  /// 「虚化」档位下限。0 就是完全不采样背后，与关闭玻璃效果同观感。
  ///
  /// 它不再是出厂值（见 [defaultSurfaceBlur]），但仍然是**坏数据的归宿**：
  /// 解析不出有效档位时退回不模糊，而不是退回满档模糊。
  static const double minSurfaceBlur = 0.0;

  /// 旧版 100% 虚化在新滑杆上对应 50%。因此这一倍率在渲染时会乘 2，
  /// 保持 50% 的实际半径与旧版满档一致；上半段允许更强的虚化。
  static const double defaultSurfaceBlur = 0.50;
  static const double surfaceBlurLegacyFullScale = 0.50;

  /// 虚化档位变了会通知这里，理由同 [surfaceOpacityListenable]：滑杆拖动时
  /// 已经建好的玻璃面要当帧重画，不能等外层重建。
  static final ValueNotifier<double> _surfaceBlurSignal = ValueNotifier<double>(
    defaultSurfaceBlur,
  );

  static ValueListenable<double> get surfaceBlurListenable =>
      _surfaceBlurSignal;

  /// 全局虚化档位（0~1）。50% 保持旧版满档强度；100% 是旧版的两倍基线。
  ///
  /// 它是**倍率**不是 sigma：各材质（顶栏、弹窗、卡片）本来就有自己的基线
  /// 半径，这一档统一缩放它们，所以同一个百分比在每块面上的实际糊度不同，
  /// 但「更糊了」的方向一致。
  static void setSurfaceBlur(double value) {
    final next = value.isFinite
        ? value.clamp(minSurfaceBlur, 1.0).toDouble()
        : defaultSurfaceBlur;
    if (next == _surfaceBlur) return;
    _surfaceBlur = next;
    _surfaceBlurSignal.value = next;
  }

  /// 此刻生效的虚化档位。关掉全部玻璃效果时一切退回不模糊。
  static double get surfaceBlur => _disableAllGlassEffects ? 0 : _surfaceBlur;

  /// 是否要为用户打开背景采样。
  ///
  /// 调用方自己声明了 `blurBehind`（全屏播放器）时不受这一档影响——播放器
  /// 的背景模糊有独立的滑杆，两套相乘会让「60」这个数字失去意义。
  static bool get userBlurEnabled => surfaceBlur > 0;

  /// 把一块面的基线模糊半径按档位缩放。
  static double scaleSurfaceBlur(double sigma) =>
      sigma * (surfaceBlur / surfaceBlurLegacyFullScale);

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

  /// 把一个「本来该是实色」的 chrome 底色，按当前档位调淡。
  ///
  /// 标题栏、tab 胶囊这些以前是写死的常量色（`0x28FFFFFF`、纯白…），滑杆
  /// 拖到 40% 时它们还是原样——用户看到的就是「这一栏不跟随设置」。统一走
  /// 这个函数，透明度会乘到各自的底色上，各自原本的浓淡差异仍然保留。
  static Color withSurfaceOpacity(Color color) =>
      color.withValues(alpha: (color.a * surfaceAlpha).clamp(0.0, 1.0));

  static void setDisableAllGlassEffects(bool disabled) {
    _disableAllGlassEffects = disabled;
    _syncBlurScale();
  }

  /// 液态玻璃（折射着色器）开关的出厂值。
  ///
  /// 默认打开，理由和「虚化」出厂满档一样：这是材质层面的主卖点，第一次进
  /// 设置页就该看到效果，而不是先去开一个开关才知道有这回事。它改变的是
  /// 「玻璃怎么成形」而不是「玻璃有多浓」——染色、不透明度、虚化三档照常
  /// 生效，只是在液态玻璃下染色会被压到很低，靠折射和高光收口。
  static const bool defaultLiquidGlass = true;

  static bool _liquidGlass = defaultLiquidGlass;

  /// 开关变了会通知这里：设置页一拨，已经建好的玻璃面要当帧换成另一种材质。
  static final ValueNotifier<bool> _liquidGlassSignal = ValueNotifier<bool>(
    defaultLiquidGlass,
  );

  static ValueListenable<bool> get liquidGlassListenable => _liquidGlassSignal;

  /// 用户是否想要液态玻璃。**不代表此刻真的用得上**——还要看着色器有没有
  /// 编译出来，见 [liquidGlass]。
  static bool get liquidGlassPreferred =>
      _liquidGlass && !_disableAllGlassEffects;

  static void setLiquidGlass(bool value) {
    if (value == _liquidGlass) return;
    _liquidGlass = value;
    _liquidGlassSignal.value = value;
  }

  /// 此刻是否真的用液态玻璃着色器。
  ///
  /// 三个条件同时成立才算：用户开着、没有整体关闭玻璃效果、且当前渲染后端
  /// 支持背景着色器滤镜。任何一条不满足都退回普通毛玻璃——宁可糊一点，也
  /// 不能画出一块既没折射也没底的透明板。
  static bool get liquidGlass =>
      liquidGlassPreferred && LiquidGlassShader.available;

  /// 液态玻璃下把毛玻璃的 sigma 折算成着色器前的模糊量。
  ///
  /// 着色器负责折射与高光，模糊只用来压住背后的细节，不需要毛玻璃那么重：
  /// 顶栏基线的 12.75 折算后约 3.8，正好是参考实现里「柔和」材质的档位；
  /// 再往上就该糊成普通毛玻璃、折射被糊没了。
  static const double liquidFrostScale = 0.3;

  static double liquidFrost(double sigma) => sigma * liquidFrostScale;

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
