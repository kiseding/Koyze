import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/player_route_progress.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/effect_policy.dart';
import '../../../../core/widgets/artwork_image.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../router/app_router.dart';
import '../../../../core/widgets/play_pulse_button.dart';
import '../player_provider.dart';
import '../../../lyric/presentation/lyric_provider.dart';
import '../../../home/presentation/widgets/mini_bar.dart';

class _MiniLyricText extends ConsumerWidget {
  final bool hasSong;
  final String fallback;
  final Color color;

  const _MiniLyricText({
    required this.hasSong,
    required this.fallback,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(currentLyricProvider);
    final currentLineIndex = ref.watch(currentLineIndexProvider);

    var subtitle = fallback;
    if (hasSong &&
        lyrics.isNotEmpty &&
        currentLineIndex >= 0 &&
        currentLineIndex < lyrics.lines.length) {
      subtitle = lyrics.lines[currentLineIndex].text;
    }

    return Text(
      subtitle,
      style: TextStyle(fontSize: 13, color: color),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 迷你播放条（v3.0.7 的排布）：一条玻璃栏，左侧封面 + 曲名/歌词，
/// 右侧作词、播放、下一首三个控件。
///
/// 材质换成和顶部 tab 胶囊同一块液态玻璃，两处 chrome 才像同一套系统。
class MiniPlayer extends ConsumerStatefulWidget {
  final bool floating;
  final bool alwaysShow;
  final GlassQuality glassQuality;

  const MiniPlayer({
    super.key,
    this.floating = false,
    this.alwaysShow = false,
    this.glassQuality = GlassQuality.premium,
  });

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  /// 已按播放器档位预热过封面的地址。
  String? _prewarmedArtwork;

  /// 迷你栏是打开全屏播放器的主入口，播放器里的飞行封面按 1080 解码。
  /// 在这一档提前预热，点开时封面已经解码好，不会先空一两帧再弹出来。
  void _prewarmPlayerArtwork(String? artwork) {
    if (artwork == null || artwork.isEmpty || artwork == _prewarmedArtwork) {
      return;
    }
    _prewarmedArtwork = artwork;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _prewarmedArtwork != artwork) return;
      precacheImage(
        ResizeImage.resizeIfNeeded(
          kPlayerArtworkDecodeWidth,
          null,
          ArtworkNetworkImage(artwork),
        ),
        context,
      ).catchError((Object _) {
        // 预热失败不影响迷你栏；打开播放器时会走正常的按需加载。
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final playerService = ref.watch(playerServiceProvider);
    _prewarmPlayerArtwork(currentMusic?.artwork);

    if (currentMusic == null && !widget.alwaysShow) {
      return const SizedBox.shrink();
    }

    final isPlayingValue = isPlaying.value ?? false;
    // 无歌曲时播放条只是占位，直接使用 Minimal 档，避免固定层在滚动时
    // 为不存在的内容付出背景采样成本。
    final quality = currentMusic == null
        ? GlassQuality.minimal
        : widget.glassQuality;

    final titleColor = AppColors.onScaffold(context);
    final subColor = AppColors.secondaryText(context);
    final surface = AppColors.fill2(context);

    final title = currentMusic?.name ?? S.of(context).notPlaying;
    final fallbackSubtitle = currentMusic?.singer ?? S.of(context).noLyrics;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: widget.floating ? kMiniBarFloatingHeight : kMiniBarHeight,
        child: LiquidGlassSurface(
          borderRadius: BorderRadius.circular(widget.floating ? 24 : 20),
          blur: 22,
          quality: quality,
          boxShadow: AppGlass.shadowFor(
            context,
            style: AppGlassStyle.bar,
            emphasized: widget.floating,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.floating ? kMiniBarFloatingPaddingLeft : kMiniBarPaddingLeft,
              7,
              kMiniBarPaddingRight,
              7,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: S.of(context).openNowPlaying,
                    button: true,
                    enabled: currentMusic != null,
                    child: InkWell(
                      onTap: currentMusic != null
                          ? () => pushPlayerRoute(context, hasSong: true)
                          : null,
                      borderRadius: BorderRadius.circular(16),
                      child: Row(
                        children: [
                          Container(
                            width: widget.floating
                                ? kMiniBarFloatingArtworkSize
                                : kMiniBarArtworkSize,
                            height: widget.floating
                                ? kMiniBarFloatingArtworkSize
                                : kMiniBarArtworkSize,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                widget.floating ? 17 : 13,
                              ),
                              color: surface,
                              border: Border.all(
                                color: AppColors.cardBorder(context),
                                width: 0.6,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ValueListenableBuilder<double>(
                              valueListenable: playerRouteProgress,
                              builder: (context, progress, child) {
                                final hideCover = progress > 0 && progress < 1;
                                return Opacity(
                                  opacity: hideCover ? 0 : 1,
                                  child: child,
                                );
                              },
                              child: AnimatedSwitcher(
                                duration: motionDuration(
                                  context,
                                  MotionDuration.normal,
                                ),
                                switchInCurve: MotionCurve.easeOut,
                                switchOutCurve: MotionCurve.easeIn,
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.90,
                                        end: 1,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: KeyedSubtree(
                                  key: ValueKey(currentMusic?.id),
                                  child:
                                      currentMusic?.artwork != null &&
                                          currentMusic!.artwork!.isNotEmpty
                                      ? ArtworkImage(
                                          currentMusic.artwork!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Icon(
                                            Icons.music_note,
                                            color: subColor,
                                            size: 27,
                                          ),
                                        )
                                      : Icon(
                                          Icons.music_note,
                                          color: subColor,
                                          size: 27,
                                        ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: titleColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                _MiniLyricText(
                                  hasSong: currentMusic != null,
                                  fallback: fallbackSubtitle,
                                  color: subColor,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: widget.floating
                      ? kMiniBarFloatingControlsWidth
                      : kMiniBarControlsWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Pressable(
                        semanticLabel: S.of(context).openLyrics,
                        onTap: currentMusic == null
                            ? null
                            : () => pushPlayerRoute(
                                context,
                                hasSong: true,
                                openLyrics: true,
                              ),
                        child: Icon(
                          Icons.subject_rounded,
                          size: widget.floating ? 28 : 32,
                          color: currentMusic == null ? subColor : titleColor,
                        ),
                      ),
                      PlayPulseButton(
                        isPlaying: isPlayingValue,
                        onPressed: currentMusic == null
                            ? null
                            : () => playerService.togglePlay(),
                        enabled: currentMusic != null,
                        size: widget.floating
                            ? kMiniBarFloatingPlaySize
                            : 38,
                        iconSize: widget.floating ? 26 : 24,
                        mini: true,
                      ),
                      Pressable(
                        semanticLabel: S.of(context).next,
                        onTap: currentMusic == null
                            ? null
                            : () => playerService.next(),
                        child: Icon(
                          Icons.skip_next_rounded,
                          size: widget.floating ? 31 : 35,
                          color: currentMusic == null ? subColor : titleColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
