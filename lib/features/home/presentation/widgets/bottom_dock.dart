import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/animations/micro_animations.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/artwork_image.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../router/app_router.dart';
import '../../../player/presentation/player_provider.dart';

/// GZ-Music 式底部 dock：图标 tab + 中间悬浮的唱片封面。
///
/// 竖屏只有这一条 chrome：四个图标 tab 均分，中间一格留给封面。条身是
/// 液态玻璃——页面内容从它底下穿过，模糊后透出颜色和形状，靠顶部亮面与
/// 0.9px 边缘线勾出轮廓，而不是靠底色盖住。上方三个播放控件是独立的一层，
/// 不挂在条上。
const double kDockBarHeight = 58;
const double kDockDiscSize = 64;
const double kDockTopOverhang = (kDockDiscSize - kDockBarHeight) / 2;
const double kDockSideMargin = 14;

/// 迷你播放控件行：居中、无底板，和 dock 隔开一段空气。
const double kMiniControlsHeight = 46;
const double kMiniControlsGap = 20;

double koyzeDockWidth(double screenWidth) {
  return (screenWidth - kDockSideMargin * 2).clamp(280.0, 520.0);
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
    center: Offset(
      screen.width / 2,
      screen.height - barBottom - kDockBarHeight / 2,
    ),
    width: kDockDiscSize,
    height: kDockDiscSize,
  );

  /// dock 组件高度：玻璃条 + 封面上下各溢出的部分。
  double get widgetHeight => kDockDiscSize;

  /// dock 组件在 Stack 里的 bottom 偏移。
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
            child: LiquidGlassSurface(
              borderRadius: BorderRadius.circular(kDockBarHeight / 2),
              boxShadow: AppGlass.shadowFor(
                context,
                style: AppGlassStyle.bar,
                emphasized: true,
              ),
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
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          child: AnimatedContainer(
            duration: motionDuration(context, MotionDuration.normal),
            curve: MotionCurve.iosSpring,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: isDark ? 0.26 : 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: isDark ? 0.40 : 0.24)
                    : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Center(
              child: AnimatedIconSwitch(
                icon: selected ? active : icon,
                keyValue: selected ? active : icon,
                size: 23,
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
    final labelSide = size * 0.64;
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
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const SizedBox.expand(),
              ),
              // 盘体纹理：细密同心纹 + 两道斜向反光，黑胶才不像一块黑饼。
              RepaintBoundary(
                child: CustomPaint(
                  size: Size.square(size),
                  painter: const _VinylGroovePainter(),
                ),
              ),
              // 盘心标签 = 当前封面。底色常驻，封面加载中也不会是黑洞。
              // 外面套一层柔和的暗影，标签才像"陷"在盘面里，不然是贴上去的圆片。
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.42),
                      blurRadius: 7,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
                child: ClipOval(
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
              ),
            ],
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

/// 黑胶盘面的纹路。
///
/// 盘心被封面盖住，所以这里只画环带：一圈圈很淡的同心纹（唱片沟槽），
/// 外加两束斜向反光。原来那两道"槽"和中心那个轴孔在 60dp 的尺寸下会缩成
/// 一个死黑点，看着像屏幕上的脏东西，索性去掉，改用整片纹理。
class _VinylGroovePainter extends CustomPainter {
  const _VinylGroovePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    // 盘心（封面）半径 0.32，留 1dp 余量让第一圈沟槽贴着封面外面。
    final inner = size.width * 0.32 + 1;

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55
      ..color = Colors.white.withValues(alpha: 0.055);
    for (var radius = inner; radius < outer - 1.2; radius += 2.1) {
      canvas.drawCircle(center, radius, groove);
    }

    // 两道略亮的主沟槽，给密纹一点节奏。
    final accentGroove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(center, inner + (outer - inner) * 0.42, accentGroove);
    canvas.drawCircle(center, inner + (outer - inner) * 0.74, accentGroove);

    // 斜向反光：两束很窄的扇形高光，像唱片转到某个角度时的那道亮边。
    final sheen = Paint()
      ..shader = SweepGradient(
        transform: const GradientRotation(-0.62),
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.13),
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.09),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0, 0.07, 0.19, 0.55, 0.63, 0.78],
      ).createShader(Rect.fromCircle(center: center, radius: outer));
    canvas.drawCircle(center, outer, sheen);

    // 外沿一圈极淡的反光收边，和玻璃条接触的地方不会出现硬边。
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = SweepGradient(
        transform: const GradientRotation(-2.2),
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0, 0.34, 0.55, 0.92],
      ).createShader(Rect.fromCircle(center: center, radius: outer));
    canvas.drawCircle(center, outer - 0.5, rim);
  }

  @override
  bool shouldRepaint(covariant _VinylGroovePainter oldDelegate) => false;
}
