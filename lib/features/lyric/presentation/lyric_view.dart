import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/lyric.dart';
import '../presentation/lyric_provider.dart';
import '../../player/presentation/player_provider.dart';
import '../../player/domain/music_item.dart';
import '../../../core/motion/motion_tokens.dart';

String _formatLyricTime(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class LyricView extends ConsumerStatefulWidget {
  final bool isFullScreen;

  const LyricView({super.key, this.isFullScreen = false});

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  final ScrollController _scrollController = ScrollController();
  int _lastScrolledIndex = -1;
  String _lyricsIdentity = '';
  bool _isUserScrolling = false;
  bool _scrollListenerAttached = false;
  bool _programmaticScroll = false;
  Timer? _resumeFollowTimer;

  double get _itemExtent => widget.isFullScreen ? 56.0 : 44.0;
  double get _verticalPadding => widget.isFullScreen ? 150.0 : 80.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrent(force: true),
    );
  }

  void _attachScrollListener() {
    if (_scrollListenerAttached || !_scrollController.hasClients) return;
    _scrollListenerAttached = true;
    _scrollController.position.isScrollingNotifier.addListener(() {
      if (_programmaticScroll) return;
      if (_scrollController.position.isScrollingNotifier.value) {
        _isUserScrolling = true;
        _resumeFollowTimer?.cancel();
      } else {
        _resumeFollowTimer?.cancel();
        _resumeFollowTimer = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          setState(() => _isUserScrolling = false);
          _lastScrolledIndex = -1;
          _scrollToCurrent(force: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _resumeFollowTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent({bool force = false}) {
    if (!mounted) return;
    final idx = ref.read(currentLineIndexProvider);
    final lyrics = ref.read(currentLyricProvider);
    if (lyrics.isEmpty || idx < 0) return;
    if (!force && (_isUserScrolling || idx == _lastScrolledIndex)) return;
    _lastScrolledIndex = idx;
    _scrollToLine(idx);
  }

  void _scrollToLine(int index) {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToLine(index);
      });
      return;
    }
    _attachScrollListener();
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    // 固定行高估算：ListView.builder 未构建的行 ensureVisible 会失败
    final rawOffset = _verticalPadding + index * _itemExtent - viewport * 0.38;
    final target = rawOffset.clamp(0.0, position.maxScrollExtent);

    _programmaticScroll = true;
    _scrollController
        .animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          _programmaticScroll = false;
        });
  }

  @override
  Widget build(BuildContext context) {
    final loadState = ref.watch(currentLyricLoadProvider);
    final lyrics = loadState.lyrics;
    final currentLineIndex = ref.watch(currentLineIndexProvider);
    final currentMusic = ref.watch(currentMusicProvider);

    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);
    final muted = AppColors.mutedText(context);
    final accent = AppColors.accentOf(context);

    // 换歌/重载歌词时强制滚到当前行
    final identity = '${currentMusic?.id ?? ''}:${lyrics.raw.hashCode}';
    if (identity != _lyricsIdentity) {
      _lyricsIdentity = identity;
      _lastScrolledIndex = -1;
      _isUserScrolling = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrent(force: true);
      });
    } else if (currentLineIndex != _lastScrolledIndex &&
        currentLineIndex >= 0 &&
        !_isUserScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrent();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _attachScrollListener(),
      );
    }

    if (loadState.isLoading) {
      return _buildStatusState(
        icon: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
        title: '正在加载歌词',
        message: currentMusic == null
            ? '正在获取歌词内容'
            : '${currentMusic.name} - ${currentMusic.singer}',
        primary: primary,
        muted: muted,
        secondary: secondary,
      );
    }

    if (loadState.error != null) {
      return _buildStatusState(
        icon: Icon(Icons.error_outline, size: 34, color: muted),
        title: '歌词加载失败',
        message: '请检查网络连接后重试',
        actionLabel: '重试',
        onAction: () => _retryLyric(currentMusic),
        primary: primary,
        muted: muted,
        secondary: secondary,
      );
    }

    if (lyrics.isEmpty) {
      return _buildStatusState(
        icon: Icon(Icons.music_note, size: 34, color: muted),
        title: '暂无歌词',
        message: currentMusic != null
            ? '${currentMusic.name} - ${currentMusic.singer}'
            : '该歌曲暂时没有可用的歌词文件',
        actionLabel: '搜索歌词',
        onAction: () => _retryLyric(currentMusic),
        primary: primary,
        muted: muted,
        secondary: secondary,
      );
    }

    final lyricList = ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.1, 0.9, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(vertical: _verticalPadding),
        itemExtent: _itemExtent,
        itemCount: lyrics.lines.length,
        itemBuilder: (context, index) {
          final line = lyrics.lines[index];
          final isCurrent = index == currentLineIndex;

          final lineColor = isCurrent
              ? accent
              : (widget.isFullScreen ? primary.withValues(alpha: 0.35) : muted);
          final dimColor = isCurrent
              ? (line.hasWordTiming
                    ? primary
                    : lineColor.withValues(alpha: 0.35))
              : lineColor;
          final transColor = isCurrent
              ? secondary
              : muted.withValues(alpha: 0.55);

          final fontSize = isCurrent
              ? (widget.isFullScreen ? 20.0 : 16.0)
              : (widget.isFullScreen ? 16.0 : 14.0);
          final weight = isCurrent ? FontWeight.bold : FontWeight.normal;

          final lineContent = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isCurrent && line.hasWordTiming)
                  _PositionedKtvLyricLine(
                    line: line,
                    lineIndex: index,
                    lyrics: lyrics,
                    // 逐字高亮始终使用主题绿色，浅色主题下也不能退化为黑色。
                    activeColor: accent,
                    dimColor: dimColor,
                    fontSize: fontSize,
                    fontWeight: weight,
                  )
                else
                  AnimatedDefaultTextStyle(
                    duration: MotionDuration.normal,
                    curve: MotionCurve.easeOut,
                    style: TextStyle(
                      color: lineColor,
                      fontSize: fontSize,
                      fontWeight: weight,
                    ),
                    child: Text(
                      line.text,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (line.translation != null)
                  AnimatedDefaultTextStyle(
                    duration: MotionDuration.normal,
                    curve: MotionCurve.easeOut,
                    style: TextStyle(
                      color: transColor,
                      fontSize: isCurrent
                          ? (widget.isFullScreen ? 13 : 11)
                          : (widget.isFullScreen ? 11 : 10),
                    ),
                    child: Text(
                      line.translation!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          );

          return GestureDetector(
            onTap: () => ref.read(seekProvider)(line.time),
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              button: true,
              selected: isCurrent,
              label: line.text,
              value: _formatLyricTime(line.time),
              onTap: () => ref.read(seekProvider)(line.time),
              child: ExcludeSemantics(child: lineContent),
            ),
          );
        },
      ),
    );

    final currentText =
        currentLineIndex >= 0 && currentLineIndex < lyrics.lines.length
        ? lyrics.lines[currentLineIndex].text
        : '';
    final previousIndex = lyrics.isEmpty || currentLineIndex < 0
        ? -1
        : (currentLineIndex - 1).clamp(0, lyrics.lines.length - 1);
    final nextIndex = lyrics.isEmpty || currentLineIndex < 0
        ? -1
        : (currentLineIndex + 1).clamp(0, lyrics.lines.length - 1);

    return Semantics(
      label: '歌词',
      value: currentText,
      decreasedValue: previousIndex < 0
          ? null
          : lyrics.lines[previousIndex].text,
      increasedValue: nextIndex < 0 ? null : lyrics.lines[nextIndex].text,
      onDecrease: previousIndex < 0
          ? null
          : () => ref.read(seekProvider)(lyrics.lines[previousIndex].time),
      onIncrease: nextIndex < 0
          ? null
          : () => ref.read(seekProvider)(lyrics.lines[nextIndex].time),
      child: lyricList,
    );
  }

  Widget _buildStatusState({
    required Widget icon,
    required String title,
    required String message,
    required Color primary,
    required Color muted,
    required Color secondary,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.fill(context),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cardBorder(context)),
              ),
              child: Center(child: icon),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(fontSize: 12, color: muted),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.fill(context),
                  foregroundColor: secondary,
                  side: BorderSide(color: AppColors.cardBorder(context)),
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _retryLyric(MusicItem? music) async {
    if (music == null) return;
    await ref.read(currentLyricLoadProvider.notifier).retry();
  }
}

class _PositionedKtvLyricLine extends ConsumerWidget {
  final LyricLine line;
  final int lineIndex;
  final Lyrics lyrics;
  final Color activeColor;
  final Color dimColor;
  final double fontSize;
  final FontWeight fontWeight;

  const _PositionedKtvLyricLine({
    required this.line,
    required this.lineIndex,
    required this.lyrics,
    required this.activeColor,
    required this.dimColor,
    required this.fontSize,
    required this.fontWeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playerPositionProvider);
    // 10Hz 逐字进度只重绘当前行，避免 ShaderMask 全列表反复离屏合成。
    return RepaintBoundary(
      child: _KtvLyricLine(
        line: line,
        lineIndex: lineIndex,
        lyrics: lyrics,
        position: position,
        activeColor: activeColor,
        dimColor: dimColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
  }
}

/// KTV 流式：已唱完的字全亮，当前字按进度裁剪填充，未唱暗色。
///
/// 平滑策略：
/// - 已唱/未唱字的 Widget 实例按活跃下标缓存复用，同一实例让框架跳过
///   无谓的重建与重排；
/// - 当前字的填充用 [TweenAnimationBuilder] 在两次位置更新之间插值，
///   把 ~10Hz 的步进渲染成逐帧连续扫过。
class _KtvLyricLine extends StatefulWidget {
  final LyricLine line;
  final int lineIndex;
  final Lyrics lyrics;
  final Duration position;
  final Color activeColor;
  final Color dimColor;
  final double fontSize;
  final FontWeight fontWeight;

  const _KtvLyricLine({
    required this.line,
    required this.lineIndex,
    required this.lyrics,
    required this.position,
    required this.activeColor,
    required this.dimColor,
    required this.fontSize,
    required this.fontWeight,
  });

  @override
  State<_KtvLyricLine> createState() => _KtvLyricLineState();
}

class _KtvLyricLineState extends State<_KtvLyricLine> {
  /// 位置更新间隔的估计值：插值时长略大于典型 tick 周期，
  /// 让当前字始终"追"向最新目标而不会停滞。
  static const Duration _fillChaseDuration = Duration(milliseconds: 120);

  int _prefixCount = -1;
  late List<Widget> _prefixChildren;
  int _suffixStart = -1;
  late List<Widget> _suffixChildren;
  int _activeIndex = -1;
  double _lastFill = 0;

  TextStyle get _textStyle => TextStyle(
    fontSize: widget.fontSize,
    fontWeight: widget.fontWeight,
    height: 1.15,
  );

  void _resetCaches() {
    _prefixCount = -1;
    _suffixStart = -1;
    _activeIndex = -1;
    _lastFill = 0;
  }

  @override
  void didUpdateWidget(covariant _KtvLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line ||
        oldWidget.lyrics != widget.lyrics ||
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.fontWeight != widget.fontWeight ||
        oldWidget.activeColor != widget.activeColor ||
        oldWidget.dimColor != widget.dimColor) {
      _resetCaches();
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.line.words!;
    final lyrics = widget.lyrics;
    final position = widget.position;
    var active = lyrics.getCurrentWordIndex(position, widget.lineIndex);

    // 行首前 / 行尾后：整行统一暗色或亮色，无需动画。
    if (active < 0 || active >= words.length) {
      final fill = active >= words.length ? 1.0 : 0.0;
      _resetCaches();
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < words.length; i++)
            _KtvWord(
              text: words[i].text,
              fill: fill,
              activeColor: widget.activeColor,
              dimColor: widget.dimColor,
              fontSize: widget.fontSize,
              fontWeight: widget.fontWeight,
            ),
        ],
      );
    }

    final textStyle = _textStyle;
    if (_prefixCount != active) {
      _prefixChildren = [
        for (var i = 0; i < active; i++)
          _KtvWord(
            text: words[i].text,
            fill: 1.0,
            activeColor: widget.activeColor,
            dimColor: widget.dimColor,
            fontSize: widget.fontSize,
            fontWeight: widget.fontWeight,
          ),
      ];
      _prefixCount = active;
    }
    final suffixStart = active + 1;
    if (_suffixStart != suffixStart) {
      _suffixChildren = [
        for (var i = suffixStart; i < words.length; i++)
          _KtvWord(
            text: words[i].text,
            fill: 0.0,
            activeColor: widget.activeColor,
            dimColor: widget.dimColor,
            fontSize: widget.fontSize,
            fontWeight: widget.fontWeight,
          ),
      ];
      _suffixStart = suffixStart;
    }

    if (_activeIndex != active) {
      _activeIndex = active;
      _lastFill = 0;
    }
    final rawFill = lyrics.getWordFillProgress(
      position,
      widget.lineIndex,
      active,
    );
    final targetFill = rawFill.clamp(0.0, 1.0);

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ..._prefixChildren,
        TweenAnimationBuilder<double>(
          key: ValueKey(active),
          tween: Tween<double>(begin: _lastFill, end: targetFill),
          duration: _fillChaseDuration,
          curve: Curves.linear,
          builder: (context, fill, child) => _PartialKtvWord(
            key: ValueKey('partial-$active'),
            text: words[active].text,
            fill: fill,
            activeColor: widget.activeColor,
            dimColor: widget.dimColor,
            style: textStyle,
          ),
        ),
        ..._suffixChildren,
      ],
    );
  }
}

/// 部分填充的当前字：底层暗色、上层主题色按比例横向裁剪。
class _PartialKtvWord extends StatelessWidget {
  final String text;
  final double fill;
  final Color activeColor;
  final Color dimColor;
  final TextStyle style;

  const _PartialKtvWord({
    super.key,
    required this.text,
    required this.fill,
    required this.activeColor,
    required this.dimColor,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (fill <= 0) {
      return Text(text, style: style.copyWith(color: dimColor));
    }
    if (fill >= 1) {
      return Text(text, style: style.copyWith(color: activeColor));
    }
    return Stack(
      children: [
        Text(text, style: style.copyWith(color: dimColor)),
        ClipRect(
          clipper: _FractionClipper(fill),
          child: Text(text, style: style.copyWith(color: activeColor)),
        ),
      ],
    );
  }
}

class _KtvWord extends StatelessWidget {
  final String text;
  final double fill;
  final Color activeColor;
  final Color dimColor;
  final double fontSize;
  final FontWeight fontWeight;

  const _KtvWord({
    required this.text,
    required this.fill,
    required this.activeColor,
    required this.dimColor,
    required this.fontSize,
    required this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: 1.15,
    );

    if (fill <= 0) {
      return Text(text, style: style.copyWith(color: dimColor));
    }
    if (fill >= 1) {
      return Text(text, style: style.copyWith(color: activeColor));
    }

    return Stack(
      children: [
        Text(text, style: style.copyWith(color: dimColor)),
        ClipRect(
          clipper: _FractionClipper(fill),
          child: Text(text, style: style.copyWith(color: activeColor)),
        ),
      ],
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  final double fraction;
  _FractionClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    final w = size.width * fraction.clamp(0.0, 1.0);
    return Rect.fromLTWH(0, 0, w, size.height);
  }

  @override
  bool shouldReclip(covariant _FractionClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
