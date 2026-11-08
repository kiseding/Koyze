import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion_tokens.dart';
import '../../../core/theme/app_colors.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/lyric.dart';
import '../presentation/lyric_provider.dart';

/// 歌词展示方式。
enum LyricLayout {
  /// 整页滚动列表（默认）。想前后找词时最有用。
  scroll,

  /// 单行：只显示当前这一行，换行时整行换掉。
  ///
  /// 锁屏、车载、小窗里最合适——没有上下文可以扫，一行大字反而读得清。
  singleLine,

  /// 轮盘：上一行 / 当前行 / 下一行竖排，越远越小越淡。
  roulette,
}

/// 单行模式的入场动画。
enum SingleLineAnimation { slideUp, fade, zoom, blur }

/// 单行 / 轮盘视图。
///
/// 两者共用同一份位置来源（[lyricPositionProvider]），所以歌词偏移、翻译、
/// 音译这些设置在这里自动生效，不需要再各写一遍。
class CompactLyricView extends ConsumerWidget {
  const CompactLyricView({
    super.key,
    required this.layout,
    required this.animation,
    this.align = Alignment.center,
  });

  final LyricLayout layout;
  final SingleLineAnimation animation;
  final Alignment align;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(currentLyricProvider);
    final index = ref.watch(currentLineIndexProvider);
    final accent = AppColors.accentOf(context);
    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);
    final scale = ref.watch(lyricScaleProvider);
    final showTranslation = ref.watch(lyricTranslationProvider);
    final showRoman = ref.watch(lyricRomanProvider);

    if (lyrics.isEmpty || index < 0 || index >= lyrics.lines.length) {
      return const SizedBox.shrink();
    }

    if (layout == LyricLayout.roulette) {
      return _RouletteLyrics(
        lyrics: lyrics,
        index: index,
        accent: accent,
        primary: primary,
        secondary: secondary,
        scale: scale,
        showTranslation: showTranslation,
        showRoman: showRoman,
        align: align,
      );
    }

    final line = lyrics.lines[index];
    return _SingleLine(
      // 换行才触发入场动画：key 跟着行号走，同一行内的逐字更新不会重放。
      key: ValueKey('${line.time.inMilliseconds}-${index}'),
      line: line,
      animation: animation,
      accent: accent,
      primary: primary,
      secondary: secondary,
      scale: scale,
      showTranslation: showTranslation,
      showRoman: showRoman,
      align: align,
    );
  }
}

class _SingleLine extends StatelessWidget {
  const _SingleLine({
    super.key,
    required this.line,
    required this.animation,
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.scale,
    required this.showTranslation,
    required this.showRoman,
    required this.align,
  });

  final LyricLine line;
  final SingleLineAnimation animation;
  final Color accent;
  final Color primary;
  final Color secondary;
  final double scale;
  final bool showTranslation;
  final bool showRoman;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: accent,
            fontSize: 22 * scale,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        if (showRoman && (line.roman?.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              line.roman!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: secondary,
                fontSize: 11.5 * scale,
                height: 1.25,
              ),
            ),
          ),
        if (showTranslation && (line.translation?.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              line.translation!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: secondary,
                fontSize: 13 * scale,
                height: 1.3,
              ),
            ),
          ),
      ],
    );

    return Align(
      alignment: align,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        // 入场用略长一点的时长：歌词换行本身就有节奏，动画太快会像闪。
        duration: MotionDuration.container,
        curve: MotionCurve.easeOut,
        builder: (context, t, child) {
          final eased = Curves.easeOutCubic.transform(t);
          switch (animation) {
            case SingleLineAnimation.fade:
              return Opacity(opacity: eased, child: child);
            case SingleLineAnimation.zoom:
              return Opacity(
                opacity: eased,
                child: Transform.scale(scale: 0.92 + 0.08 * eased, child: child),
              );
            case SingleLineAnimation.blur:
              // 由虚到实的入场。blur 半径收得比透明度快一点，看起来更"对上焦"。
              return Opacity(
                opacity: eased,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 6 * (1 - eased),
                    sigmaY: 6 * (1 - eased),
                  ),
                  child: child,
                ),
              );
            case SingleLineAnimation.slideUp:
              return Opacity(
                opacity: eased,
                child: Transform.translate(
                  offset: Offset(0, 14 * (1 - eased)),
                  child: child,
                ),
              );
          }
        },
        child: content,
      ),
    );
  }
}

/// 上一行 / 当前行 / 下一行竖排，越远越小越淡。
///
/// 不做真正的三维旋转：手机上有 30% 的概率看起来像倾斜的表格。缩放 + 透明度
/// 的层次已经足够表达"轮盘"，而且能保持文字清晰。
class _RouletteLyrics extends StatelessWidget {
  const _RouletteLyrics({
    required this.lyrics,
    required this.index,
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.scale,
    required this.showTranslation,
    required this.showRoman,
    required this.align,
  });

  final Lyrics lyrics;
  final int index;
  final Color accent;
  final Color primary;
  final Color secondary;
  final double scale;
  final bool showTranslation;
  final bool showRoman;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    for (var delta = -2; delta <= 2; delta++) {
      final i = index + delta;
      if (i < 0 || i >= lyrics.lines.length) continue;
      final isCurrent = delta == 0;
      final distance = delta.abs();
      final opacity = isCurrent ? 1.0 : (distance == 1 ? 0.42 : 0.18);
      final sizeFactor = isCurrent ? 1.0 : (distance == 1 ? 0.72 : 0.58);
      lines.add(
        AnimatedOpacity(
          duration: MotionDuration.normal,
          opacity: opacity,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: isCurrent ? 10 : 6),
            child: Transform.scale(
              scale: sizeFactor,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    lyrics.lines[i].text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? accent : primary,
                      fontSize: 20 * scale,
                      fontWeight: isCurrent
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  if (isCurrent && showRoman &&
                      (lyrics.lines[i].roman?.isNotEmpty ?? false))
                    Text(
                      lyrics.lines[i].roman!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 11.5 * scale,
                      ),
                    ),
                  if (isCurrent && showTranslation &&
                      (lyrics.lines[i].translation?.isNotEmpty ?? false))
                    Text(
                      lyrics.lines[i].translation!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 13 * scale,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: align,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }
}
