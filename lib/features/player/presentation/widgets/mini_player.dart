import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/player_route_progress.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/artwork_image.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/origo_chrome.dart';
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

/// 迷你播放控件行：三个按钮居中、悬浮、不铺底板。
///
/// 竖屏的封面已经移到 tab dock 中间，迷你条不再需要卡片；只有这三个
/// 控件浮在内容之上，页面背景可以直接透出来。
class MiniPlayerControls extends ConsumerWidget {
  const MiniPlayerControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final enabled = currentMusic != null;
    final onScaffold = AppColors.onScaffold(context);

    // 没有歌时这几个按钮无事可做，直接不出现：dock 中间的唱片才是入口。
    if (!enabled) return const SizedBox.shrink();

    return SizedBox(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _BareControl(
            semanticLabel: S.of(context).openLyrics,
            icon: Icons.subject_rounded,
            size: 25,
            color: onScaffold,
            onTap: () => pushPlayerRoute(
              context,
              hasSong: true,
              openLyrics: true,
            ),
          ),
          const SizedBox(width: 34),
          PlayPulseButton(
            isPlaying: isPlaying.value ?? false,
            onPressed: () => ref.read(playerServiceProvider).togglePlay(),
            enabled: true,
            size: 44,
            iconSize: 25,
            mini: true,
          ),
          const SizedBox(width: 34),
          _BareControl(
            semanticLabel: S.of(context).next,
            icon: Icons.skip_next_rounded,
            size: 30,
            color: onScaffold,
            onTap: () => ref.read(playerServiceProvider).next(),
          ),
        ],
      ),
    );
  }
}

/// 无底板的图标控件：只留按压缩放，不画形状。
class _BareControl extends StatelessWidget {
  const _BareControl({
    required this.icon,
    required this.size,
    required this.color,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      scale: 0.88,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          icon,
          size: size,
          color: color,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}


class MiniPlayer extends ConsumerStatefulWidget {
  final bool floating;
  final bool alwaysShow;

  const MiniPlayer({super.key, this.floating = false, this.alwaysShow = false});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {  @override
  Widget build(BuildContext context) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final playerService = ref.watch(playerServiceProvider);

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
        height: widget.floating ? 78 : 66,
        child: OrigoChromeSurface(
          borderRadius: BorderRadius.circular(widget.floating ? 24 : 20),
          accent: currentMusic == null ? AppColors.accentOf(context) : null,
          emphasized: widget.floating,
          child: Padding(
            padding: EdgeInsets.fromLTRB(widget.floating ? 10 : 8, 7, 7, 7),
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
                            width: widget.floating ? 62 : 50,
                            height: widget.floating ? 62 : 50,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                widget.floating ? 17 : 13,
                              ),
                              color: surface,
                              border: Border.all(
                                color: AppColors.cardBorder(context),
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
                                    fontSize: widget.floating ? 15 : 15,
                                    fontWeight: FontWeight.w700,
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
                  width: widget.floating ? 164 : 180,
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
                        size: widget.floating ? 44 : 38,
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
