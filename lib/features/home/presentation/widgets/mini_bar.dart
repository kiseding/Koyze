import 'package:flutter/widgets.dart';

/// 底部迷你播放条（v3.0.7 样式）的几何。
///
/// 竖屏只有这一条 chrome：一条从底边浮起、左右留边的玻璃卡，左边封面 +
/// 曲名/歌词，右边三个控件。播放页收起时的飞行封面、播放键都从这个矩形
/// 起飞，所以壳层和播放页共用同一份数字。
const double kMiniBarHeight = 66;
const double kMiniBarSideMargin = 12;
const double kMiniBarBottomGap = 8;

/// 卡片内部的封面尺寸与内边距，和 `MiniPlayer` 的非浮动布局一致。
const double kMiniBarArtworkSize = 50;
const double kMiniBarPaddingLeft = 8;
const double kMiniBarPaddingRight = 7;
const double kMiniBarControlsWidth = 180;

class KoyzeMiniBarMetrics {
  KoyzeMiniBarMetrics({required this.screen, required this.bottomInset});

  final Size screen;
  final double bottomInset;

  double get sideMargin => kMiniBarSideMargin;

  double get width =>
      (screen.width - kMiniBarSideMargin * 2).clamp(0.0, screen.width);

  /// 玻璃卡底边距屏幕底边。
  double get bottom => bottomInset + kMiniBarBottomGap;

  Rect get barRect => Rect.fromLTWH(
    kMiniBarSideMargin,
    screen.height - bottom - kMiniBarHeight,
    width,
    kMiniBarHeight,
  );

  /// 卡片左侧的封面方块。
  Rect get artworkRect => Rect.fromLTWH(
    barRect.left + kMiniBarPaddingLeft,
    barRect.top + (kMiniBarHeight - kMiniBarArtworkSize) / 2,
    kMiniBarArtworkSize,
    kMiniBarArtworkSize,
  );

  /// 播放键：右侧控件区居中那一格。
  Rect get playRect => Rect.fromCenter(
    center: Offset(
      barRect.right - kMiniBarPaddingRight - kMiniBarControlsWidth / 2,
      barRect.center.dy,
    ),
    width: 38,
    height: 38,
  );

  /// 页面内容需要让出的底部高度。
  double get contentObstruction => bottom + kMiniBarHeight + 6;
}
