// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/glass_config.dart';
import 'liquid_glass_filter.dart';

/// 玻璃材质共用的背景采样层。
///
/// 默认不采样。调用方通过 [allowBlur] 决定是否应用实时模糊，虚化半径为 0 时
/// 直接绘制子内容，省去背景捕获。
///
/// 1. **液态玻璃**（[LiquidGlassBackdrop]，见 shaders/liquid_glass.frag）。
///    设置里打开液态玻璃、且当前后端编译出了着色器时，背景不再只是被模糊，
///    而是在边缘按斯涅尔定律弯折、分通道色散、并按法线打高光。此时 [sigma]
///    只当作着色器前的模糊量（乘 [GlassEffectConfig.liquidFrostScale]）。
///    这条路径需要 [radius]，没有圆角信息的面仍然是矩形。
///
/// 2. **分组采样**（[BackdropFilter.grouped] + [BackdropGroup]）。
///    同一个 [BackdropGroup] 下互不重叠的玻璃可以复用背景捕获，减少重复采样。
///
/// 3. **有界模糊**（[ImageFilterConfig.blur] 的 `bounded`）。
///    默认模糊的采样源会超出控件矩形（高斯核半径的三倍），一块 40pt 高的胶囊
///    也要按整屏去准备离屏面；`bounded` 把采样源限制在控件自身矩形内。
///
///    但**当前默认关闭**：Flutter 自己的 Cupertino 弹窗也因为
///    flutter/flutter#182066 还没解决而停在 `bounded: false`。默认开启等于
///    赌一个已知有问题的引擎路径，等那个 issue 关掉再打开这里。
///
/// 重叠的玻璃不能共用采样键。叠在滚动内容上方的背板可通过 [shareBackdrop]
/// 独立采样，确保能读到前面已绘制的卡片和文字。
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({
    super.key,
    required this.sigma,
    required this.child,
    this.saturation,
    this.bounded = false,
    this.tileMode = ui.TileMode.mirror,
    this.allowBlur = false,
    this.shareBackdrop = true,
    this.radius,
    this.legible = false,
  });

  /// 高斯模糊标准差。小于等于 0 时直接返回 [child]，连图层都不建。
  ///
  /// 液态玻璃下这不是最终 sigma，而是先乘 [GlassEffectConfig.liquidFrostScale]
  /// 再交给着色器——折射本身已经让画面「不平」了，糊满档反而看不出折射。
  final double sigma;

  /// 是否真的采样背后的内容做模糊。
  final bool allowBlur;

  /// 是否使用外层 [BackdropGroup] 的采样键。浮在其他玻璃面上的控件应独立采样。
  final bool shareBackdrop;

  /// 饱和度倍率。为 null 时不做颜色矩阵，少一次逐像素运算。
  final double? saturation;

  /// 采样源是否限制在控件自身矩形内。见类注释。
  final bool bounded;

  final ui.TileMode tileMode;

  /// 玻璃圆角（逻辑像素）。为 null 时不走液态玻璃——着色器要靠它算玻璃形状。
  final double? radius;

  /// 玻璃上压着文字时置 true：液态玻璃会给这块面加一层很淡的色调，压低
  /// 背后内容的对比度，否则下面的列表文字会和这块玻璃自己的标题叠在一起。
  final bool legible;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 开关一切换就要当帧换材质。不能只靠外层（app.dart 重建）——路由配置
    // 没变时子树不会被重建，设置页里那块预览就会停在旧材质上。
    return ListenableBuilder(
      listenable: GlassEffectConfig.liquidGlassListenable,
      builder: (context, _) => _buildGlass(context),
    );
  }

  Widget _buildGlass(BuildContext context) {
    final liquidRadius = radius;
    if (liquidRadius != null && GlassEffectConfig.liquidGlass) {
      // 液态玻璃自带折射，不采样就什么都没有，因此不看 allowBlur。
      return LiquidGlassBackdrop(
        radius: liquidRadius,
        frost: GlassEffectConfig.liquidFrost(sigma),
        legible: legible,
        child: child,
      );
    }

    if (sigma <= 0 || !allowBlur) return child;

    final config = _resolveConfig();
    if (!shareBackdrop || BackdropGroup.of(context) == null) {
      return BackdropFilter(filterConfig: config, child: child);
    }
    return BackdropFilter.grouped(filterConfig: config, child: child);
  }

  ImageFilterConfig _resolveConfig() {
    final blur = ImageFilterConfig.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: tileMode,
      bounded: bounded,
    );
    final saturate = saturation;
    if (saturate == null || (saturate - 1).abs() < 0.001) return blur;
    // 先做饱和度，再模糊：与原先 `ImageFilter.compose(outer: blur, inner: 矩阵)`
    // 的先后顺序一致，观感不变。
    return ImageFilterConfig.compose(
      outer: blur,
      inner: ImageFilterConfig(
        ColorFilter.matrix(glassSaturationMatrix(saturate)),
      ),
    );
  }
}

/// 把 [BorderRadius] 折算成液态玻璃着色器要的单一圆角。
///
/// 着色器按正圆弧算玻璃形状，只认一个半径。四角不一致（底部面板常见的
/// 「上圆下方」）或椭圆角的面折算出来会和实际裁剪对不上，宁可不走液态玻璃、
/// 退回普通毛玻璃，也不画一圈对不齐的折射边。
double? uniformGlassRadius(BorderRadius radius) {
  final corner = radius.topLeft;
  if (corner.x != corner.y) return null;
  if (radius.topRight != corner ||
      radius.bottomLeft != corner ||
      radius.bottomRight != corner) {
    return null;
  }
  return corner.x;
}

/// 围绕 Rec.709 亮度缩放饱和度的 5x4 颜色矩阵。
List<double> glassSaturationMatrix(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final ir = 1 - s;
  return <double>[
    ir * r + s,
    ir * g,
    ir * b,
    0,
    0,
    ir * r,
    ir * g + s,
    ir * b,
    0,
    0,
    ir * r,
    ir * g,
    ir * b + s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}
