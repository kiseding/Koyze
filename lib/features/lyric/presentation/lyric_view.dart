import 'dart:async';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/lyric.dart';
import '../presentation/lyric_provider.dart';
import 'interlude_dots.dart';
import 'lyric_effects.dart';
import 'lyric_font_provider.dart';
import 'word_motion.dart';
import '../../player/presentation/player_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../player/domain/music_item.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/widgets/loading_widget.dart';

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

  /// 是否已经完整显示过一次歌词。首屏那次不播入场动画（页面转场已经够了），
  /// 之后每次从加载态回到歌词都算换歌，值得播。
  bool _entrancePlayedOnce = false;

  Timer? _resumeFollowTimer;

  double get _baseItemExtent => widget.isFullScreen ? 56.0 : 44.0;
  double get _verticalPadding => widget.isFullScreen ? 150.0 : 80.0;

  /// 行高随内容与字号变化。
  ///
  /// `ListView.builder` 用了 [itemExtent]，滚动定位才能靠 `index * extent` 直接
  /// 算出来（未构建的行拿不到 `RenderObject`）。代价是每行高度必须一致：多出
  /// 音译/翻译一行就要把整个行高一起抬高，否则最后一行会被裁掉。
  double _itemExtent(Lyrics lyrics, double scale) {
    final hasTranslation = lyrics.lines.any(
      (line) => line.translation != null && line.translation!.isNotEmpty,
    );
    return _baseItemExtent * scale + (hasTranslation ? 15.0 * scale : 0.0);
  }

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

  void _scrollToLine(int index, {double? extent, double? align}) {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToLine(index, extent: extent, align: align);
      });
      return;
    }
    _attachScrollListener();
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final itemExtent =
        extent ??
        _itemExtent(
          ref.read(currentLyricProvider),
          ref.read(lyricScaleProvider),
        );
    final double anchor = align ?? ref.read<double>(lyricAlignProvider);
    // 固定行高估算：ListView.builder 未构建的行 ensureVisible 会失败
    final rawOffset = _verticalPadding + index * itemExtent - viewport * anchor;
    final target = rawOffset.clamp(0.0, position.maxScrollExtent);

    _programmaticScroll = true;
    if (reduceMotion(context)) {
      _scrollController.jumpTo(target);
      _programmaticScroll = false;
      return;
    }
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
        icon: AppLoadingIndicator(strokeWidth: 2.5, color: accent),
        title: S.of(context).lyricsLoading,
        message: currentMusic == null
            ? S.of(context).fetchingLyrics
            : '${currentMusic.name} - ${currentMusic.singer}',
        primary: primary,
        muted: muted,
        secondary: secondary,
      );
    }

    if (loadState.error != null) {
      return _buildStatusState(
        icon: Icon(Icons.error_outline, size: 34, color: muted),
        title: S.of(context).lyricsFailed,
        message: S.of(context).checkNetwork,
        actionLabel: S.of(context).retry,
        onAction: () => _retryLyric(currentMusic),
        primary: primary,
        muted: muted,
        secondary: secondary,
      );
    }

    if (lyrics.isEmpty) {
      return _buildStatusState(
        icon: Icon(Icons.music_note, size: 34, color: muted),
        title: S.of(context).lyricsEmpty,
        message: currentMusic != null
            ? '${currentMusic.name} - ${currentMusic.singer}'
            : S.of(context).lyricsUnavailable,
        actionLabel: S.of(context).searchLyrics,
        onAction: () => _retryLyric(currentMusic),
        primary: primary,
        muted: muted,
        secondary: secondary,
      );
    }

    final scale = ref.watch(lyricScaleProvider);
    final showTranslation = ref.watch(lyricTranslationProvider);
    final blurAmount = ref.watch(lyricBlurProvider);
    // 进到这一段说明歌词已经拿到并要画出来了。置位放在 build 里而不是动画
    // 结束回调里：动画中途被打断（用户马上又切歌）也不该让下一首歌少播一次。
    final playEntranceOnMount = _entrancePlayedOnce;
    _entrancePlayedOnce = true;
    final entrance =
        LyricEntranceStyle.values[ref.watch(lyricEntranceProvider).clamp(0, 3)];
    // 自定义字体的字体族是异步注册的：没注册好之前 family 为 null，退回主题
    // 字体，注册完成后这个 provider 一变，整段歌词就换成新字体。
    final lyricFamily = ref.watch(lyricFontProvider).family;
    final itemExtent = _itemExtent(lyrics, scale);
    Color fadeByDistance(Color base, int index) {
      if (currentLineIndex < 0) return base;
      final distance = (index - currentLineIndex).abs();
      if (distance <= 1) return base;
      final factor = (1.0 - (distance - 1) * 0.2).clamp(0.2, 1.0);
      return base.withValues(alpha: base.a * factor);
    }

    final lyricList = ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(vertical: _verticalPadding),
      itemExtent: itemExtent,
      itemCount: lyrics.lines.length,
      itemBuilder: (context, index) {
        final line = lyrics.lines[index];
        final isCurrent = index == currentLineIndex;

        final rawLineColor = isCurrent
            ? accent
            : (widget.isFullScreen ? primary.withValues(alpha: 0.35) : muted);
        final lineColor = fadeByDistance(rawLineColor, index);
        final dimColor = isCurrent
            ? (line.hasWordTiming ? primary : lineColor.withValues(alpha: 0.35))
            : lineColor;
        final transColor = fadeByDistance(
          isCurrent ? secondary : muted.withValues(alpha: 0.55),
          index,
        );

        final baseFontSize = isCurrent
            ? (widget.isFullScreen ? 20.0 : 16.0)
            : (widget.isFullScreen ? 16.0 : 14.0);
        final fontSize = baseFontSize * scale;
        final weight = isCurrent ? FontWeight.bold : FontWeight.normal;

        // AnimatedDefaultTextStyle 的样式是整体替换而非合并：直接给一个裸
        // TextStyle 会把主题字体（以及中文回退）一起丢掉。
        final baseStyle = DefaultTextStyle.of(context).style;
        final blur = lyricBlurSigmaFor(
          distance: (index - currentLineIndex).abs(),
          amount: blurAmount,
        );

        final lineContent = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 整行套一层动画样式，而不是给 Text 单独套：当前行放大时，逐字
              // 歌词也要跟着同一个插值变大。分开套的话，切到 KTV 的那一帧
              // 字号会直接跳到终值，看起来就是"闪一下"。
              lyricBlurred(
                AnimatedDefaultTextStyle(
                  duration: MotionDuration.normal,
                  curve: MotionCurve.easeOut,
                  style: baseStyle.copyWith(
                    color: lineColor,
                    fontFamily: lyricFamily,
                    fontSize: fontSize,
                    fontWeight: weight,
                    height: 1.15,
                  ),
                  child: isCurrent && line.hasWordTiming
                      ? _PositionedKtvLyricLine(
                          line: line,
                          lineIndex: index,
                          lyrics: lyrics,
                          // 逐字高亮始终使用主题绿色，浅色主题下也不能退化为黑色。
                          activeColor: accent,
                          dimColor: dimColor,
                        )
                      : Text(
                          line.text,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                blur,
              ),
              if (showTranslation &&
                  line.translation != null &&
                  line.translation!.isNotEmpty)
                lyricBlurred(
                  AnimatedDefaultTextStyle(
                    duration: MotionDuration.normal,
                    curve: MotionCurve.easeOut,
                    style: baseStyle.copyWith(
                      color: transColor,
                      fontFamily: lyricFamily,
                      fontSize: (isCurrent ? 13.0 : 11.0) * scale,
                      height: 1.15,
                    ),
                    child: Text(
                      line.translation!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  blur,
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

    final interlude = _resolveInterlude(lyrics, currentLineIndex);
    // 列表永远待在同一个 Stack 里，间奏点只是浮在上面的一层。
    //
    // 之前是「有间奏才包一层 Stack」：进到长间奏那一行时树结构从 ListView
    // 变成 Stack(ListView)，ListView 会被整个摘下来重建，滚动位置有一帧是
    // 0，看起来就是歌词闪一下再滚回去——而且刚好发生在换行的瞬间。
    final body = LyricEntrance(
      style: entrance,
      // 换歌才重放：同一个播放位置的重建不该让整片歌词再进场一次。
      playKey: currentMusic?.id ?? '',
      // 换歌一定会先过「正在加载歌词」，那段时间本组件被摘出树，回来时是新
      // State，playKey 那条路径永远走不到。首屏有页面转场，不再叠一次动画；
      // 之后每次重新挂载都意味着换了歌，交给动画。
      playOnMount: playEntranceOnMount,
      child: Stack(
        children: [
          Positioned.fill(child: lyricList),
          if (interlude != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _scrollController,
                  builder: (context, _) {
                    if (!_scrollController.hasClients) {
                      return const SizedBox.shrink();
                    }
                    // 下一行的槽位（列表按固定行高排布，可以算术定位）。
                    final top =
                        _verticalPadding +
                        interlude.nextLineIndex * itemExtent -
                        _scrollController.offset;
                    return Stack(
                      children: [
                        Positioned(
                          top: top,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: InterludeDots(
                              start: interlude.start,
                              end: interlude.end,
                              position: () => ref.read(lyricPositionProvider),
                              color: accent.withValues(alpha: 0.85),
                              dotSize: widget.isFullScreen ? 4.5 : 3.5,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      label: S.of(context).lyrics,
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
      child: body,
    );
  }

  /// 判断当前行之后是否存在一段值得画呼吸点的间奏。
  ///
  /// 判定依据是「到下一行的间隔」而不是「这一行唱了多久」——普通 LRC 没有行
  /// 结束时间，间隔是唯一可靠信号。间隔超过 3.8s 才画，否则间奏点会和正常的
  /// 换行重叠，看起来像卡顿。
  ({int nextLineIndex, Duration start, Duration end})? _resolveInterlude(
    Lyrics lyrics,
    int currentLineIndex,
  ) {
    if (currentLineIndex < 0 || currentLineIndex + 1 >= lyrics.lines.length) {
      return null;
    }
    final current = lyrics.lines[currentLineIndex];
    final next = lyrics.lines[currentLineIndex + 1];
    final gap = next.time - current.time;
    if (gap < const Duration(milliseconds: 3800)) return null;

    // 有逐字时间时，最后一个字唱完就是本行的真实结束点。
    Duration lineEnd = current.time;
    final words = current.words;
    if (words != null && words.isNotEmpty) {
      final last = words.last;
      lineEnd = last.time + (last.duration ?? Duration.zero);
    } else {
      final guess = gap * 0.45;
      lineEnd =
          current.time +
          (guess > const Duration(milliseconds: 2500)
              ? const Duration(milliseconds: 2500)
              : guess);
    }
    if (lineEnd <= current.time) lineEnd = current.time;
    if (lineEnd >= next.time) return null;

    return (
      nextLineIndex: currentLineIndex + 1,
      start: lineEnd,
      end: next.time,
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

  const _PositionedKtvLyricLine({
    required this.line,
    required this.lineIndex,
    required this.lyrics,
    required this.activeColor,
    required this.dimColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 读的是歌词时间轴（已叠加用户校准偏移），不是原始播放进度。
    final position = ref.watch(lyricPositionProvider);
    final playing = ref.watch(isPlayingProvider).valueOrNull ?? false;
    // 10Hz 逐字进度只重绘当前行，避免整列表反复离屏合成。
    return RepaintBoundary(
      child: _KtvLyricLine(
        line: line,
        lineIndex: lineIndex,
        lyrics: lyrics,
        position: position,
        activeColor: activeColor,
        dimColor: dimColor,
        playing: playing,
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

  /// 正在播放时才逐帧推进动画；暂停时停表，避免歌词自己往前跑。
  final bool playing;

  const _KtvLyricLine({
    required this.line,
    required this.lineIndex,
    required this.lyrics,
    required this.position,
    required this.activeColor,
    required this.dimColor,
    required this.playing,
  });

  @override
  State<_KtvLyricLine> createState() => _KtvLyricLineState();
}

class _KtvLyricLineState extends State<_KtvLyricLine>
    with SingleTickerProviderStateMixin {
  /// 本地推进的播放位置。
  ///
  /// 播放器每 100ms 才推一次位置，用这个值直接算动画会看到明显的台阶。这里
  /// 用 ticker 按帧推进，只在外部位置与本地推算偏差过大（拖动、跳转、暂停后
  /// 恢复）时才对齐一次。
  Duration _local = Duration.zero;
  Duration _lastElapsed = Duration.zero;
  Ticker? _ticker;
  bool _ticking = false;

  @override
  void initState() {
    super.initState();
    _local = widget.position;
  }

  @override
  void didUpdateWidget(covariant _KtvLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line ||
        oldWidget.lyrics != widget.lyrics ||
        oldWidget.activeColor != widget.activeColor ||
        oldWidget.dimColor != widget.dimColor) {
      _local = widget.position;
      _lastElapsed = Duration.zero;
    } else {
      final drift = (widget.position - _local).abs();
      // 100ms 的正常步进不该被拉回，否则本地推进毫无意义；超过 250ms
      // 只可能是 seek / 切歌 / 暂停恢复，必须对齐。
      if (drift > const Duration(milliseconds: 250)) {
        _local = widget.position;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    if (!mounted) return;
    setState(() => _local += delta);
  }

  void _ensureTicking(bool shouldTick) {
    if (shouldTick) {
      if (_ticking) return;
      _ticking = true;
      _lastElapsed = Duration.zero;
      _ticker ??= createTicker(_onTick);
      _ticker!.start();
    } else if (_ticking) {
      _ticking = false;
      _ticker?.stop();
    }
  }

  /// 词的结束时间：有 duration 就用它，没有就按下一个词的起点估算。
  int _wordEndMs(int index, List<LyricWord> words, int lineStartMs) {
    final word = words[index];
    final start = word.time.inMilliseconds;
    final explicit = word.duration?.inMilliseconds ?? 0;
    if (explicit > 0) return start + explicit;
    if (index + 1 < words.length) return words[index + 1].time.inMilliseconds;
    return start + 400;
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.line.words!;
    final lineStartMs = widget.line.time.inMilliseconds;
    final positionMs = _local.inMilliseconds;
    final lineEndMs = _wordEndMs(words.length - 1, words, lineStartMs);
    final playing = widget.playing;

    // 只有这一行真的在唱的时候才逐帧推进：整页歌词里同时只有一行会是
    // active 行，成本可控；行外空转等于让引擎永远不休眠。
    _ensureTicking(
      playing &&
          positionMs >= lineStartMs - 250 &&
          positionMs <= lineEndMs + 250,
    );

    final active = widget.lyrics.getCurrentWordIndex(_local, widget.lineIndex);
    final relativeMs = (positionMs - lineStartMs).toDouble();

    // 字号和字重来自外层 AnimatedDefaultTextStyle：当前行变大的那 280ms 里，
    // 逐字歌词必须跟着同一条曲线一起插值，自己取终值就会在切换的那一帧跳一下。
    final inherited = DefaultTextStyle.of(context).style;
    final fontSize = inherited.fontSize ?? 16.0;
    final fontWeight = inherited.fontWeight ?? FontWeight.bold;
    final fontFamily = inherited.fontFamily;

    final children = <Widget>[
      for (var i = 0; i < words.length; i++)
        _animatedWord(
          index: i,
          words: words,
          active: active,
          relativeMs: relativeMs,
          lineStartMs: lineStartMs,
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
        ),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  /// 单个词的位移 / 缩放 / 辉光 / 填充比例。
  Widget _animatedWord({
    required int index,
    required List<LyricWord> words,
    required int active,
    required double relativeMs,
    required int lineStartMs,
    required double fontSize,
    required FontWeight fontWeight,
    required String? fontFamily,
  }) {
    final word = words[index];
    final startMs = word.time.inMilliseconds - lineStartMs;
    final endMs = _wordEndMs(index, words, lineStartMs) - lineStartMs;
    final emphasized = shouldEmphasize(
      durationMs: endMs - startMs,
      text: word.text,
    );
    final motion = solveWordMotion(
      positionMs: relativeMs,
      wordStartMs: startMs.toDouble(),
      wordEndMs: endMs.toDouble(),
      isEmphasized: emphasized,
    );
    final fill = index < active
        ? 1.0
        : (index == active
              ? widget.lyrics
                    .getWordFillProgress(_local, widget.lineIndex, index)
                    .clamp(0.0, 1.0)
              : 0.0);

    final child = _PartialKtvWord(
      text: word.text,
      fill: fill,
      activeColor: widget.activeColor,
      dimColor: widget.dimColor,
      glowAlpha: motion.glowAlpha,
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: 1.15,
      ),
    );

    if (motion == WordMotion.idle) return child;
    return Transform.translate(
      offset: Offset(0, motion.offsetEm * fontSize),
      child: motion.scale == 1
          ? child
          : Transform.scale(scale: motion.scale, child: child),
    );
  }
}

/// 部分填充的当前字：底层暗色、上层主题色按比例横向裁剪。
class _PartialKtvWord extends StatelessWidget {
  final String text;
  final double fill;
  final Color activeColor;
  final Color dimColor;

  /// 长词强调的辉光强度 0~1。
  final double glowAlpha;
  final TextStyle style;

  const _PartialKtvWord({
    required this.text,
    required this.fill,
    required this.activeColor,
    required this.dimColor,
    required this.style,
    this.glowAlpha = 0,
  });

  TextStyle _glow(TextStyle base, Color color) {
    if (glowAlpha <= 0.01) return base;
    return base.copyWith(
      shadows: [
        Shadow(
          color: color.withValues(alpha: color.a * glowAlpha * 0.55),
          blurRadius: 12,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (fill <= 0) {
      return Text(text, style: style.copyWith(color: dimColor));
    }
    if (fill >= 1) {
      return Text(
        text,
        style: _glow(style, activeColor).copyWith(color: activeColor),
      );
    }
    return Stack(
      children: [
        Text(text, style: style.copyWith(color: dimColor)),
        ClipRect(
          clipper: _FractionClipper(fill),
          child: Text(
            text,
            style: _glow(style, activeColor).copyWith(color: activeColor),
          ),
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
