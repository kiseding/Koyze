import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/player_route_progress.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/artwork_image.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../router/app_router.dart';
import '../../../../core/widgets/play_pulse_button.dart';
import '../player_provider.dart';
import '../../../lyric/presentation/lyric_provider.dart';

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

/// 迷你播放条。进度条去掉后，封面和控件按空出的高度等比放大。

class MiniPlayer extends ConsumerStatefulWidget {
  final bool floating;
  final bool alwaysShow;

  const MiniPlayer({super.key, this.floating = false, this.alwaysShow = false});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final playerService = ref.watch(playerServiceProvider);
    final isDark = AppColors.isDark(context);

    if (currentMusic == null && !widget.alwaysShow) {
      return const SizedBox.shrink();
    }

    final isPlayingValue = isPlaying.value ?? false;

    final titleColor = AppColors.onScaffold(context);
    final subColor = AppColors.secondaryText(context);
    final surface = AppColors.fill2(context);

    final title = currentMusic?.name ?? S.of(context).notPlaying;
    final fallbackSubtitle = currentMusic?.singer ?? S.of(context).noLyrics;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: 66,
        child: GlassSurface(
          style: AppGlassStyle.bar,
          borderRadius: BorderRadius.circular(20),
          boxShadow: widget.floating
              ? [
                  BoxShadow(
                    color: isDark
                        ? const Color(0x66000000)
                        : const Color(0x1A000000),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 2, 0),
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
                      borderRadius: BorderRadius.circular(13),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              color: surface,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ValueListenableBuilder<double>(
                              valueListenable: playerRouteProgress,
                              builder: (context, progress, child) {
                                // 动效期间隐藏迷你栏真封面，只留飞行快照封面。
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
                                        begin: 0.94,
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
                          const SizedBox(width: 13),
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
                  width: 180,
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
                          size: 32,
                          color: currentMusic == null ? subColor : titleColor,
                        ),
                      ),
                      PlayPulseButton(
                        isPlaying: isPlayingValue,
                        onPressed: currentMusic == null
                            ? null
                            : () => playerService.togglePlay(),
                        enabled: currentMusic != null,
                        size: 38,
                        iconSize: 24,
                        mini: true,
                      ),
                      Pressable(
                        semanticLabel: S.of(context).next,
                        onTap: currentMusic == null
                            ? null
                            : () => playerService.next(),
                        child: Icon(
                          Icons.skip_next_rounded,
                          size: 35,
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
