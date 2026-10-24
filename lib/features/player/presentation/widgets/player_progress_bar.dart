// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion_tokens.dart';

/// 全屏播放器进度条的几何计算。
///
/// 单独抽出来是为了能被测试直接钉住：进度条开头的「小尖角」问题一旦回归，
/// 单元测试比截图更容易发现。
@immutable
class PlayerProgressGeometry {
  const PlayerProgressGeometry({
    required this.thumbLeft,
    required this.fillWidth,
  });

  /// 圆形滑块的左边缘（相对轨道左端）。
  final double thumbLeft;

  /// 已播放部分的宽度，从轨道左端算起。
  final double fillWidth;

  static const double trackHeight = 16;
  static const double thumbSize = 20;
  static const double thumbRadius = thumbSize / 2;

  /// 已播放部分至少露出这么宽才绘制。
  ///
  /// 更低进度时圆角会被压成 1~3px 的细尖角，贴在滑块左侧，看起来像渲染残影。
  static const double minVisibleFill = 4;

  factory PlayerProgressGeometry.resolve({
    required double trackWidth,
    required double ratio,
  }) {
    final width = trackWidth.isFinite && trackWidth > 0 ? trackWidth : 0.0;
    final progress = ratio.isFinite ? ratio.clamp(0.0, 1.0) : 0.0;
    final maxLeft = math.max(0.0, width - thumbSize);
    final center = width * progress;
    final thumbLeft = (center - thumbRadius).clamp(0.0, maxLeft);

    // 填充画到滑块左缘，滑块把填充左端完全盖住，低进度时不会在滑块
    // 左侧露出一段浅色月牙。滑块还压在起点上时（左缘尚未离开起点）整段
    // 不画，避免起点凸出细尖角。滑块已到最右端时画满整条轨道。
    double fillWidth;
    if (thumbLeft < minVisibleFill) {
      fillWidth = 0.0;
    } else if (thumbLeft >= maxLeft) {
      fillWidth = width;
    } else {
      fillWidth = thumbLeft;
    }

    return PlayerProgressGeometry(
      thumbLeft: thumbLeft,
      fillWidth: fillWidth,
    );
  }
}

/// 全屏播放器的进度条本体（轨道 + 已播放填充 + 圆形滑块）。
///
/// 交互由外层 `_PlayerProgress` 的 [GestureDetector] 负责，这里只负责画。
class PlayerProgressBar extends StatelessWidget {
  const PlayerProgressBar({
    super.key,
    required this.ratio,
    required this.accentColor,
    required this.trackColor,
    this.seeking = false,
    this.animationDuration = const Duration(milliseconds: 150),
  });

  /// 播放进度，0..1。
  final double ratio;

  /// 已播放部分的颜色，同时用于滑块的辉光。
  final Color accentColor;

  /// 未播放轨道的颜色。
  final Color trackColor;

  /// 手指按住拖动时为 true，滑块会放大。
  final bool seeking;

  final Duration animationDuration;

  static const ValueKey<String> fillKey = ValueKey('player-progress-fill');
  static const ValueKey<String> thumbKey = ValueKey('player-progress-thumb');

  /// 滑块比已播放部分略深，避免和填充连成一片。
  static Color thumbColorOf(Color accent) =>
      Color.alphaBlend(Colors.black.withValues(alpha: 0.2), accent);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final geometry = PlayerProgressGeometry.resolve(
          trackWidth: width,
          ratio: ratio,
        );
        final thumbColor = thumbColorOf(accentColor);
        const trackRadius = PlayerProgressGeometry.trackHeight / 2;

        return SizedBox(
          width: width,
          height: PlayerProgressGeometry.trackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 轨道与填充一起裁成圆角：低进度时填充不会从轨道左端的
              // 圆角轮廓里鼓出来。
              ClipRRect(
                borderRadius: BorderRadius.circular(trackRadius),
                child: SizedBox(
                  width: width,
                  height: PlayerProgressGeometry.trackHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: trackColor)),
                      if (geometry.fillWidth > 0)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: geometry.fillWidth,
                          child: DecoratedBox(
                            key: fillKey,
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(trackRadius),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: geometry.thumbLeft,
                top: (PlayerProgressGeometry.trackHeight -
                        PlayerProgressGeometry.thumbSize) /
                    2,
                child: AnimatedScale(
                  scale: seeking ? 1.35 : 1.0,
                  duration: animationDuration,
                  curve: MotionCurve.iosSpring,
                  child: Container(
                    key: thumbKey,
                    width: PlayerProgressGeometry.thumbSize,
                    height: PlayerProgressGeometry.thumbSize,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      shape: BoxShape.circle,
                      // 辉光要克制：过大半径 + 半透明深色在浅色背景上会
                      // 扩散成一圈「发白灰绿」的残影，像滑块左侧多出一段
                      // 月牙。这里用接近不透明的同色、紧贴滑块的小光晕。
                      boxShadow: [
                        BoxShadow(
                          color: thumbColor.withValues(alpha: 0.9),
                          blurRadius: 2,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
