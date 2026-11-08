// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 玻璃材质的背景采样层。整个 App 只从这里创建 [BackdropFilter]。
///
/// 两个开关都不是"调参"，而是省掉引擎侧的真实工作量：
///
/// 1. **分组采样**（[BackdropFilter.grouped] + [BackdropGroup]）。
///    默认每个 [BackdropFilter] 各自把"自己下面已经画好的整屏"拷进离屏纹理。
///    首页一屏十块玻璃就是十次全屏拷贝；平移一屏时十块都要重抓，这就是横滑
///    掉帧的来源。同一个 [BackdropGroup] 下的玻璃共用一次背景捕获，引擎只
///    做一次模糊，再把结果按各自的裁剪区域贴回去。
///
/// 2. **有界模糊**（[ImageFilterConfig.blur] 的 `bounded`）。
///    默认模糊的采样源会超出控件矩形（高斯核半径的三倍），一块 40pt 高的胶囊
///    也要按整屏去准备离屏面；`bounded` 把采样源限制在控件自身矩形内。
///
///    但**当前默认关闭**：Flutter 自己的 Cupertino 弹窗也因为
///    flutter/flutter#182066 还没解决而停在 `bounded: false`。默认开启等于
///    赌一个已知有问题的引擎路径，等那个 issue 关掉再打开这里。
///
/// 注意：**互相重叠**的玻璃不要共用同一个 group（重叠区域会变成只有一层模糊，
/// 因为共用的是同一份输入）。浮在页面之上、会压到页面玻璃的 chrome（迷你播放
/// 条）因此留在 group 外面，走独立采样。
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({
    super.key,
    required this.sigma,
    required this.child,
    this.saturation,
    this.bounded = false,
    this.tileMode = ui.TileMode.mirror,
  });

  /// 高斯模糊标准差。小于等于 0 时直接返回 [child]，连图层都不建。
  final double sigma;

  /// 饱和度倍率。为 null 时不做颜色矩阵，少一次逐像素运算。
  final double? saturation;

  /// 采样源是否限制在控件自身矩形内。见类注释。
  final bool bounded;

  final ui.TileMode tileMode;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (sigma <= 0) return child;

    final config = _resolveConfig();
    // 没有外层分组时退回普通采样，行为与改动前一致。
    if (BackdropGroup.of(context) == null) {
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
