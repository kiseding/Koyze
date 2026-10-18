import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/animations/micro_animations.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/artwork_image.dart';
import '../../../../core/widgets/origo_chrome.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../router/app_router.dart';
import '../../../player/presentation/player_provider.dart';

/// GZ-Music 式底部 dock：图标 tab + 中间悬浮的唱片封面。
///
/// 竖屏只有这一条 chrome：四个图标 tab 均分，中间一格留给封面，封面比
/// 玻璃条高出 3dp，四面留出的浅色柔边就是它的"浮起"感。迷你播放条的三个
/// 控件不再占一条卡片，而是浮在这条 dock 上方。
const double kDockBarHeight = 52;
const double kDockDiscSize = 58;
const double kDockTopOverhang = (kDockDiscSize - kDockBarHeight) / 2;
const double kDockSideMargin = 16;

/// 迷你播放控件行：居中、无底板。
const double kMiniControlsHeight = 46;
const double kMiniControlsGap = 14;

double koyzeDockWidth(double screenWidth) {
  return (screenWidth - kDockSideMargin * 2).clamp(280.0, 560.0);
}

/// dock 与迷你控件行的几何。壳层与播放页 morph 共用同一份数字，
/// 展开/收起时封面不会从错的位置起飞。
class KoyzeDockMetrics {
  KoyzeDockMetrics({required this.screen, required this.bottomInset})
    : bottomSpacing = bottomInset == 0 ? 2.0 : 0.0,
      bottomClearance = bottomInset == 0 ? 11.0 : 0.0;

  final Size screen;
  final double bottomInset;

  /// 有系统手势条时贴边，没有时留 2dp 让玻璃边不被裁。
  final double bottomSpacing;

  /// 悬浮 dock 与屏幕底边的呼吸距离（仅在没有系统 inset 时生效）。
  final double bottomClearance;

  double get width => koyzeDockWidth(screen.width);

  /// 玻璃条底边距屏幕底边。
  double get barBottom => bottomInset + bottomSpacing + bottomClearance;

  /// 玻璃条顶边距屏幕底边。
  double get barTop => barBottom + kDockBarHeight;

  Rect get barRect => Rect.fromLTWH(
    (screen.width - width) / 2,
    screen.height - barTop,
    width,
    kDockBarHeight,
  );

  /// 中间唱片封面：水平居中，垂直对齐玻璃条中线。
  Rect get discRect => Rect.fromCenter(
    center: Offset(screen.width / 2, screen.height - barBottom - kDockBarHeight / 2),
    width: kDockDiscSize,
    height: kDockDiscSize,
  );

  /// dock 组件（62 高，含上下各 3dp 溢出）在 Stack 里的 bottom 偏移。
  double get dockWidgetBottom => barBottom - kDockTopOverhang;

  /// 迷你控件行底边距屏幕底边。
  double get controlsBottom => barTop + kMiniControlsGap;

  /// 控件行里播放键的中心区域。
  Rect get controlsPlayRect => Rect.fromCenter(
    center: Offset(
      screen.width / 2,
      screen.height - controlsBottom - kMiniControlsHeight / 2,
    ),
    width: 44,
    height: 44,
  );

  /// 页面内容需要让出的底部高度（dock + 控件行）。
  double get contentObstruction =>
      controlsBottom + kMiniControlsHeight + 4;
}

class KoyzeBottomDock extends ConsumerWidget {
  const KoyzeBottomDock({
    super.key,
    required this.metrics,
    required this.selectedIndex,
    required this.onTap,
  });

  final KoyzeDockMetrics metrics;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return SizedBox(
      width: metrics.width,
      height: kDockDiscSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: kDockTopOverhang,
            bottom: kDockTopOverhang,
            child: OrigoChromeSurface(
              borderRadius: BorderRadius.circular(kDockBarHeight / 2),
              emphasized: true,
              child: Row(
                children: [
                  _tab(
                    context,
                    index: 0,
                    icon: Icons.home_outlined,
                    active: Icons.home,
                    label: s.home,
                  ),
                  _tab(
                    context,
                    index: 1,
                    icon: Icons.leaderboard_outlined,
                    active: Icons.leaderboard,
                    label: s.charts,
                  ),
                  // 中间：留白给封面，同时保持五格等宽。
                  const Expanded(child: SizedBox.expand()),
                  _tab(
                    context,
                    index: 2,
                    icon: Icons.library_music_outlined,
                    active: Icons.library_music,
                    label: s.playlists,
                  ),
                  _tab(
                    context,
                    index: 3,
                    icon: Icons.settings_outlined,
                    active: Icons.settings,
                    label: s.settings,
                  ),
                ],
              ),
            ),
          ),
          const DockArtworkDisc(),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData active,
    required String label,
  }) {
    final selected = index == selectedIndex;
    final accent = AppColors.accentOf(context);
    final isDark = AppColors.isDark(context);
    // 未选中也要在玻璃上看得清，但纯黑 90% 会比选中项更"重"。
    final muted = isDark ? const Color(0xD9FFFFFF) : const Color(0xD9000000);
    return Expanded(
      child: Pressable(
        semanticLabel: label,
        selected: selected,
        onTap: () => onTap(index),
        scale: 0.9,
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: AnimatedContainer(
            duration: motionDuration(context, MotionDuration.normal),
            curve: MotionCurve.iosSpring,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: isDark ? 0.20 : 0.13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: isDark ? 0.32 : 0.18)
                    : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Center(
              child: AnimatedIconSwitch(
                icon: selected ? active : icon,
                keyValue: selected ? active : icon,
                size: 22,
                color: selected ? accent : muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// dock 中间的唱片。点击进入全屏播放器（与原迷你栏封面一致）。
class DockArtworkDisc extends ConsumerWidget {
  const DockArtworkDisc({super.key, this.size = kDockDiscSize});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentMusicProvider);
    final hasTrack = track != null;
    final artwork = track?.artwork;
    final accent = AppColors.accentOf(context);
    final labelSide = size * 0.60;
    final s = S.of(context);

    return Semantics(
      button: true,
      enabled: hasTrack,
      label: s.openNowPlaying,
      child: Pressable(
        semanticLabel: s.openNowPlaying,
        onTap: hasTrack ? () => pushPlayerRoute(context, hasSong: true) : null,
        scale: 0.93,
        borderRadius: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 唱片本体：黑胶外圈。
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF2C2C31), Color(0xFF0A0A0C)],
                    stops: [0.5, 1],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.38),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const SizedBox.expand(),
              ),
              // 两道浅槽，唱片才不像一块黑色圆片。
              _groove(size * 0.86),
              _groove(size * 0.74),
              // 盘心标签 = 当前封面。底色常驻，封面加载中也不会是黑洞。
              ClipOval(
                child: Container(
                  width: labelSide,
                  height: labelSide,
                  color: accent.withValues(alpha: hasTrack ? 0.62 : 0.46),
                  child: artwork != null && artwork.isNotEmpty
                      ? ArtworkImage(
                          artwork,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
              // 轴孔。
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0B0B0D),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                    width: 0.7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groove(double side) {
    return IgnorePointer(
      child: Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.055),
            width: 0.7,
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.32,
        color: Colors.white.withValues(alpha: 0.92),
      ),
    );
  }
}
