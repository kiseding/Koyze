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

/// 左右两侧留白。歌词紧贴屏幕边缘时，标点会被裁掉半截。
const double _kSidePadding = 26;

/// 单行模式正文最大宽度。平板横屏时一行铺满会很难读。
const double _kMaxTextWidth = 660;

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

    final centered = align == Alignment.center;

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
        centered: centered,
      );
    }

    return _SingleLine(
      line: lyrics.lines[index],
      index: index,
      animation: animation,
      accent: accent,
      secondary: secondary,
      scale: scale,
      showTranslation: showTranslation,
      showRoman: showRoman,
      align: align,
      centered: centered,
    );
  }
}

/// 单行歌词：一次只存在一行，换行时新旧两行交叉过渡。
class _SingleLine extends StatelessWidget {
  const _SingleLine({
    required this.line,
    required this.index,
    required this.animation,
    required this.accent,
    required this.secondary,
    required this.scale,
    required this.showTranslation,
    required this.showRoman,
    required this.align,
    required this.centered,
  });

  final LyricLine line;
  final int index;
  final SingleLineAnimation animation;
  final Color accent;
  final Color secondary;
  final double scale;
  final bool showTranslation;
  final bool showRoman;
  final Alignment align;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final duration = reduce ? Duration.zero : MotionDuration.normal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kSidePadding),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxTextWidth),
          child: _LineTransition(
            duration: duration,
            alignment: centered ? Alignment.center : Alignment.centerLeft,
            transition: _transition,
            child: _LineBlock(
              // 换行才换 key：同一行内的逐字更新不会重放入场动画。
              key: ValueKey('${line.time.inMilliseconds}-$index'),
              line: line,
              accent: accent,
              secondary: secondary,
              scale: scale,
              showTranslation: showTranslation,
              showRoman: showRoman,
              centered: centered,
            ),
          ),
        ),
      ),
    );
  }

  /// [progress] 是整段过渡的时间线（0→1），新旧两行共用。
  ///
  /// 旧行退得更快（1.6 倍速）：两行按同一速度交叉时，中段几十毫秒里两句话
  /// 都接近全不透明、叠在同一处，看起来就是糊成一团的重影。
  Widget _transition(Widget child, double progress, {required bool outgoing}) {
    final t = progress.clamp(0.0, 1.0);
    final eased = outgoing
        ? 1 - Curves.easeOutCubic.transform((t * 1.6).clamp(0.0, 1.0))
        : Curves.easeOutCubic.transform(t);
    switch (animation) {
      case SingleLineAnimation.fade:
        return Opacity(opacity: eased, child: child);
      case SingleLineAnimation.zoom:
        // 缩放入点比透明稍晚收完，看起来像"对上焦"而不是单纯放大。
        return Opacity(
          opacity: eased,
          child: Transform.scale(scale: 0.94 + 0.06 * eased, child: child),
        );
      case SingleLineAnimation.blur:
        if (eased >= 0.999) return child;
        return Opacity(
          opacity: eased,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 7 * (1 - eased),
              sigmaY: 7 * (1 - eased),
            ),
            child: child,
          ),
        );
      case SingleLineAnimation.slideUp:
        // 新行从下面顶上来，旧行往上面让出去，两者不会在同一高度撞上。
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, (outgoing ? -12 : 16) * (1 - eased)),
            child: child,
          ),
        );
    }
  }
}

/// 单行歌词的交叉过渡。
///
/// 没有用 [AnimatedSwitcher]：这套 Flutter 的 AnimatedSwitcher 在 initState
/// 里按 0 进度构建首个 child，之后不会自己重建（只在 didUpdateWidget 时重算），
/// 首帧于是永远是透明的——用户看到的就是"切歌/切词时闪一下"。
///
/// 这里让控制器从 1 起步：第一行上来就是可见的；只有换行才从 0 重放，
/// 并且新旧两行同时在场，任何一帧都不会空。
class _LineTransition extends StatefulWidget {
  const _LineTransition({
    required this.child,
    required this.duration,
    required this.alignment,
    required this.transition,
  });

  final Widget child;
  final Duration duration;
  final Alignment alignment;
  final Widget Function(Widget child, double progress, {required bool outgoing})
  transition;

  @override
  State<_LineTransition> createState() => _LineTransitionState();
}

class _LineTransitionState extends State<_LineTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Widget? _outgoing;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration, value: 1)
          ..addStatusListener((status) {
            // 过渡结束就把旧行摘掉，别让它一直挂在树上。
            if (status == AnimationStatus.completed && _outgoing != null) {
              setState(() => _outgoing = null);
            }
          });
  }

  @override
  void didUpdateWidget(covariant _LineTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    // 只有换行（key 变了）才重放；同一行的翻译/音译更新、或者纯粹的父级
    // 重建，都不该再放一遍入场动画。这里比的是 key 的值而不是实例：
    // ValueKey 每次 build 都是新对象，identical 会永远为 false。
    if (widget.child.key == oldWidget.child.key) return;
    _outgoing = oldWidget.child;
    if (_controller.duration == Duration.zero) {
      _outgoing = null;
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Stack(
          alignment: widget.alignment,
          children: [
            if (_outgoing != null)
              // 两行吃同一条时间线，各自按自己的曲线换算透明度。
              widget.transition(_outgoing!, _controller.value, outgoing: true),
            widget.transition(widget.child, _controller.value, outgoing: false),
          ],
        );
      },
    );
  }
}

/// 原文 / 音译 / 翻译三层文字，单行模式的内容块。
class _LineBlock extends StatelessWidget {
  const _LineBlock({
    super.key,
    required this.line,
    required this.accent,
    required this.secondary,
    required this.scale,
    required this.showTranslation,
    required this.showRoman,
    required this.centered,
  });

  final LyricLine line;
  final Color accent;
  final Color secondary;
  final double scale;
  final bool showTranslation;
  final bool showRoman;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final hasRoman = showRoman && (line.roman?.isNotEmpty ?? false);
    final hasTranslation =
        showTranslation && (line.translation?.isNotEmpty ?? false);
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          line.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            color: accent,
            fontSize: 23 * scale,
            fontWeight: FontWeight.w700,
            // 1.28 而不是 1.2：两行折行时，汉字方块之间需要一点呼吸。
            height: 1.28,
            letterSpacing: 0.2,
          ),
        ),
        if (hasRoman)
          Padding(
            padding: EdgeInsets.only(top: 6 * scale),
            child: Text(
              line.roman!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: TextStyle(
                color: secondary,
                fontSize: 12 * scale,
                height: 1.3,
                letterSpacing: 0.3,
              ),
            ),
          ),
        if (hasTranslation)
          Padding(
            padding: EdgeInsets.only(top: (hasRoman ? 3 : 6) * scale),
            child: Text(
              line.translation!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: TextStyle(
                color: secondary,
                fontSize: 13.5 * scale,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }
}

/// 上一行 / 当前行 / 下一行竖排，越远越小越淡。
///
/// 不做真正的三维旋转：手机上有 30% 的概率看起来像倾斜的表格。
///
/// 尺寸直接改字号而不是 `Transform.scale`：后者缩放的是画好的像素，布局高度
/// 还是按原字号占位，越远的行留出的空档越大，五行排下来间距忽宽忽窄。
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
    required this.centered,
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
  final bool centered;

  /// 每个槽位的字号倍率，下标是 |距离|。中心行最大，往外收窄。
  static const List<double> _sizeByDistance = [1.0, 0.72, 0.60];

  @override
  Widget build(BuildContext context) {
    final duration = motionDuration(context, MotionDuration.normal);
    final rows = <Widget>[];
    for (var delta = -2; delta <= 2; delta++) {
      final i = index + delta;
      if (i < 0 || i >= lyrics.lines.length) continue;
      final distance = delta.abs();
      final line = lyrics.lines[i];
      rows.add(
        _RouletteRow(
          // 用行号做 key：换行时同一行会从"下一行"滑到"当前行"，key 不变，
          // 字号和透明度才能接着上一帧插值，而不是换一段全新的文字。
          key: ValueKey(i),
          line: line,
          isCurrent: delta == 0,
          distance: distance,
          accent: accent,
          primary: primary,
          secondary: secondary,
          scale: scale,
          showTranslation: showTranslation,
          showRoman: showRoman,
          centered: centered,
          duration: duration,
          fontSize: 20 * scale * _sizeByDistance[distance.clamp(0, 2)],
          opacity: delta == 0 ? 1.0 : (distance == 1 ? 0.5 : 0.24),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kSidePadding),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxTextWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ),
    );
  }
}

class _RouletteRow extends StatelessWidget {
  const _RouletteRow({
    super.key,
    required this.line,
    required this.isCurrent,
    required this.distance,
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.scale,
    required this.showTranslation,
    required this.showRoman,
    required this.centered,
    required this.duration,
    required this.fontSize,
    required this.opacity,
  });

  final LyricLine line;
  final bool isCurrent;
  final int distance;
  final Color accent;
  final Color primary;
  final Color secondary;
  final double scale;
  final bool showTranslation;
  final bool showRoman;
  final bool centered;
  final Duration duration;
  final double fontSize;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    // 同 lyric_view：AnimatedDefaultTextStyle 不合并继承样式，裸 TextStyle
    // 会把主题字体族丢掉。
    final base = DefaultTextStyle.of(context).style;
    return AnimatedOpacity(
      duration: duration,
      curve: MotionCurve.easeOut,
      opacity: opacity,
      child: AnimatedPadding(
        duration: duration,
        curve: MotionCurve.easeOut,
        // 只用字号撑开间距是不够的：当前行上下还要多留一点，视线才落得住。
        padding: EdgeInsets.symmetric(vertical: isCurrent ? 7 : 4),
        child: AnimatedDefaultTextStyle(
          duration: duration,
          curve: MotionCurve.easeOut,
          style: base.copyWith(
            color: isCurrent ? accent : primary,
            fontSize: fontSize,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            height: 1.3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                line.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
              ),
              if (isCurrent && showRoman && (line.roman?.isNotEmpty ?? false))
                Padding(
                  padding: EdgeInsets.only(top: 4 * scale),
                  child: Text(
                    line.roman!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: textAlign,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 11.5 * scale,
                      height: 1.35,
                    ),
                  ),
                ),
              if (isCurrent &&
                  showTranslation &&
                  (line.translation?.isNotEmpty ?? false))
                Padding(
                  padding: EdgeInsets.only(top: 3 * scale),
                  child: Text(
                    line.translation!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: textAlign,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12.5 * scale,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
