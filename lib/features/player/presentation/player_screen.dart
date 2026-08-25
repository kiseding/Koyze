import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pagination/page_range.dart';
import '../../../core/player_route_progress.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/page_navigation_bar.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/play_pulse_button.dart';
import '../../../core/network/play_url_result.dart';
import '../domain/music_item.dart';
import '../domain/player_service.dart';
import 'player_provider.dart';
import 'scrub_session.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../sync/presentation/sync_phase1_provider.dart';
import '../../playlist/presentation/playlist_picker.dart';
import '../../playlist/data/playlist_repository.dart';
import '../../download/presentation/download_provider.dart';
import '../../lyric/presentation/lyric_view.dart';
import '../../lyric/presentation/lyric_provider.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../core/motion/motion_tokens.dart';

double _playbackQueueSheetInitialSize(BuildContext context, int itemCount) {
  final screenHeight = MediaQuery.sizeOf(context).height;
  if (screenHeight <= 0) return 0.58;
  const headerHeight = 94.0;
  const tileHeight = 56.0;
  const extraHeight = 50.0;
  const maxSheetSize = 0.78;
  final visibleRows = itemCount <= 0 ? 1 : itemCount.clamp(1, 8);
  final targetHeight = headerHeight + visibleRows * tileHeight + extraHeight;
  return (targetHeight / screenHeight).clamp(0.28, maxSheetSize).toDouble();
}

String _formatPlayerDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _CurrentLyricLine extends ConsumerStatefulWidget {
  const _CurrentLyricLine();

  @override
  ConsumerState<_CurrentLyricLine> createState() => _CurrentLyricLineState();
}

class _CurrentLyricLineState extends ConsumerState<_CurrentLyricLine>
    with SingleTickerProviderStateMixin {
  /// 仅在进入播放器时延迟淡入一次；PageView 页面切换不重播，
  /// 避免歌词预览（黄行）在切换动画中与歌名重叠。
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: kFullPlayerTrackSwitchDuration,
  );
  bool _started = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _fade.value = 1;
    } else {
      _fade.forward();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(currentLyricProvider);
    final currentLineIndex = ref.watch(currentLineIndexProvider);

    String text = ' ';
    String? translation;
    var hasLine = false;
    if (lyrics.isNotEmpty &&
        currentLineIndex >= 0 &&
        currentLineIndex < lyrics.lines.length) {
      final line = lyrics.lines[currentLineIndex];
      text = line.text.isEmpty ? ' ' : line.text;
      translation = line.translation;
      hasLine = true;
    }

    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: hasLine
                      ? AppColors.secondaryText(context)
                      : AppColors.mutedText(context).withValues(alpha: 0.01),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                translation ?? ' ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: translation != null
                      ? AppColors.mutedText(context)
                      : AppColors.mutedText(context).withValues(alpha: 0.01),
                  fontSize: 11,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerProgress extends ConsumerWidget {
  final Duration duration;
  final bool seeking;
  final double seekValue;
  final void Function(double value) onDragStart;
  final void Function(double value) onDragUpdate;
  final Future<void> Function(Duration target) onSeekEnd;
  final VoidCallback onSeekCancel;
  final Future<void> Function(double value, Duration target) onTapSeek;

  const _PlayerProgress({
    required this.duration,
    required this.seeking,
    required this.seekValue,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onSeekEnd,
    required this.onSeekCancel,
    required this.onTapSeek,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playerPositionProvider);
    final totalMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final effectivePos = seeking
        ? Duration(milliseconds: (seekValue * totalMs).round())
        : position;
    final ratio = (effectivePos.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final displayPos = effectivePos;

    Duration adjusted(Duration position, int deltaSeconds) {
      final milliseconds = (position.inMilliseconds + deltaSeconds * 1000)
          .clamp(0, duration.inMilliseconds);
      return Duration(milliseconds: milliseconds);
    }

    // 10Hz 进度更新只重绘进度条自身，避免波及整页（封面/阴影/遮罩）。
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              child: Text(
                _formatPlayerDuration(displayPos),
                style: TextStyle(
                  color: AppColors.mutedText(context),
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final interactiveTrack = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (d) {
                      onDragStart((d.localPosition.dx / width).clamp(0.0, 1.0));
                    },
                    onHorizontalDragUpdate: (d) {
                      onDragUpdate(
                        (d.localPosition.dx / width).clamp(0.0, 1.0),
                      );
                    },
                    onHorizontalDragEnd: (_) {
                      final target = Duration(
                        milliseconds: (seekValue * totalMs).round(),
                      );
                      onSeekEnd(target);
                    },
                    onHorizontalDragCancel: onSeekCancel,
                    onTapUp: (d) {
                      final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
                      final target = Duration(
                        milliseconds: (v * totalMs).round(),
                      );
                      onTapSeek(v, target);
                    },
                    child: SizedBox(
                      height: 28,
                      child: Center(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppColors.cardBorder(context),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: ratio,
                              child: Container(
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppColors.accentOf(context),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                            Positioned(
                              left: (width * ratio - 9).clamp(0.0, width - 18),
                              top: -4,
                              child: AnimatedScale(
                                scale: seeking ? 1.35 : 1.0,
                                duration: motionDuration(
                                  context,
                                  const Duration(milliseconds: 150),
                                ),
                                curve: Curves.easeOutCubic,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: AppColors.accentOf(context),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.accentOf(
                                          context,
                                        ).withAlpha(120),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                  return Semantics(
                    label: '播放进度',
                    slider: true,
                    enabled: duration > Duration.zero,
                    value:
                        '${_formatPlayerDuration(displayPos)} / ${_formatPlayerDuration(duration)}',
                    increasedValue: _formatPlayerDuration(
                      adjusted(displayPos, 10),
                    ),
                    decreasedValue: _formatPlayerDuration(
                      adjusted(displayPos, -10),
                    ),
                    onIncrease: duration > Duration.zero
                        ? () => ref.read(seekProvider)(adjusted(displayPos, 10))
                        : null,
                    onDecrease: duration > Duration.zero
                        ? () =>
                              ref.read(seekProvider)(adjusted(displayPos, -10))
                        : null,
                    child: ExcludeSemantics(child: interactiveTrack),
                  );
                },
              ),
            ),
            const SizedBox(width: 5),
            SizedBox(
              width: 36,
              child: Text(
                _formatPlayerDuration(duration),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppColors.mutedText(context),
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const kFullPlayerTrackSwitchDuration = Duration(milliseconds: 620);
const kFullPlayerTrackSwitchReverseDuration = Duration(milliseconds: 420);

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  late bool _seeking;
  double _seekValue = 0; // 0..1 only while finger is down
  bool _wasPlayingBeforeSeek = false;
  late final ScrubSession _scrubSession;
  ScrubOperation? _dragOperation;
  double _dragOffset = 0;
  bool _draggingDown = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrubSession = ScrubSession(
      begin: ref.read(beginScrubProvider),
      finish: ref.read(finishScrubProvider),
      cancel: ref.read(cancelScrubProvider),
    );
    _seeking = false;
  }

  void _cancelActiveScrub() {
    final operation = _dragOperation;
    _dragOperation = null;
    final cancelledCurrent = operation != null
        ? _scrubSession.cancel(operation)
        : false;
    if (cancelledCurrent) _seeking = false;
  }

  @override
  void dispose() {
    _dragOperation = null;
    _scrubSession.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = ref.watch(playerServiceProvider);
    final currentMusic = ref.watch(currentMusicProvider);
    // 窄 watch：只订阅 playing 变化，避免 playbackState 其它字段
    // （position/buffered 等高频更新）触发整页重建。
    final isPlaying = ref.watch(
      playbackStateProvider.select((s) => s.value?.playing ?? false),
    );
    final playMode = ref.watch(playModeProvider);

    if (currentMusic == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.music_note,
                size: 64,
                color: AppColors.mutedText(context),
              ),
              SizedBox(height: 16),
              Text(
                '暂无播放内容',
                style: TextStyle(color: AppColors.mutedText(context)),
              ),
            ],
          ),
        ),
      );
    }

    final duration = ref.watch(durationProvider).value ?? currentMusic.duration;

    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final dismissThreshold = screenH * 0.4; // 超过 2/5 关闭
    // 下拉时露出下层路由（打开前的界面）
    final revealT = (_dragOffset / (screenH * 0.45)).clamp(0.0, 1.0);

    return ValueListenableBuilder<double>(
      valueListenable: playerRouteProgress,
      builder: (context, progress, _) {
        // 固定页面布局，只让可见窗口在迷你栏和全屏之间变化。这样关闭时
        // 内容不会被压扁，迷你栏也能在窗口收拢的最后阶段自然接管。
        final media = MediaQuery.of(context);
        final bottomInset = media.padding.bottom > media.viewPadding.bottom
            ? media.padding.bottom
            : media.viewPadding.bottom;
        final bottomSpacing = bottomInset == 0 ? 6.0 : 0.0;
        final navHeight =
            37.0 + bottomInset + bottomSpacing + (bottomInset == 0 ? 3.0 : 0.0);
        const miniHeight = 78.0;
        const gap = 7.0;
        final miniLeft = 3.0;
        final miniWidth = screenW - 6.0;
        final miniBottom = navHeight + gap;
        final miniRect = Rect.fromLTWH(
          miniLeft,
          screenH - miniBottom - miniHeight,
          miniWidth,
          miniHeight,
        );
        final fullRect = Offset.zero & Size(screenW, screenH);
        final morphT = Curves.easeOutCubic.transform(progress);
        final currentRect = Rect.lerp(miniRect, fullRect, morphT)!;
        final contentOpacity = ((progress - 0.08) / 0.72).clamp(0.0, 1.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: currentRect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16 * (1 - morphT)),
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: screenW,
                    maxWidth: screenW,
                    minHeight: screenH,
                    maxHeight: screenH,
                    child: Opacity(
                      opacity: contentOpacity,
                      child: _buildPlayerBody(
                        context,
                        currentMusic,
                        playerService,
                        isPlaying,
                        playMode,
                        duration,
                        screenH,
                        screenW,
                        dismissThreshold,
                        revealT,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 播放器主体（含拖拽收起手势）。
  Widget _buildPlayerBody(
    BuildContext context,
    dynamic currentMusic,
    dynamic playerService,
    bool isPlaying,
    dynamic playMode,
    Duration duration,
    double screenH,
    double screenW,
    double dismissThreshold,
    double revealT,
  ) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 轻遮罩：仅拖拽时挂载（下拉时淡出透出上一页），
          // 避免整屏半透明层在正常播放时白费 fill-rate。
          if (_draggingDown || _dragOffset > 0)
            IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.28 * (1 - revealT)),
              ),
            ),
          AnimatedContainer(
            duration: _draggingDown
                ? Duration.zero
                : motionDuration(context, const Duration(milliseconds: 220)),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, _dragOffset, 0),
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              elevation: 8,
              shadowColor: Colors.black54,
              child: SafeArea(
                child: GestureDetector(
                  onVerticalDragStart: (_) {
                    setState(() {
                      _draggingDown = true;
                      _dragOffset = 0;
                    });
                  },
                  onVerticalDragUpdate: (d) {
                    if (d.delta.dy > 0 || _dragOffset > 0) {
                      setState(() {
                        _dragOffset = (_dragOffset + d.delta.dy).clamp(
                          0.0,
                          screenH,
                        );
                      });
                    }
                  },
                  onVerticalDragEnd: (d) {
                    final shouldClose =
                        _dragOffset > dismissThreshold ||
                        (d.primaryVelocity ?? 0) > 900;
                    if (shouldClose) {
                      Navigator.of(context).maybePop();
                    } else {
                      setState(() {
                        _draggingDown = false;
                        _dragOffset = 0;
                      });
                    }
                  },
                  child: Column(
                    children: [
                      _StaggeredFade(
                        delay: 0.55,
                        child: _buildAppBar(context, currentMusic),
                      ),
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (index) =>
                              setState(() => _currentPage = index),
                          // 不缓存相邻页：封面/歌词互斥，页面切换无动画干扰。
                          allowImplicitScrolling: false,
                          children: [
                            Column(
                              children: [
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _buildArtwork(
                                    currentMusic.artwork,
                                    songId: currentMusic.id,
                                  ),
                                ),
                                _StaggeredFade(
                                  delay: 0.2,
                                  child: _buildSongInfo(currentMusic),
                                ),
                                _StaggeredFade(
                                  delay: 0.3,
                                  child: const _CurrentLyricLine(),
                                ),
                                _StaggeredFade(
                                  delay: 0.45,
                                  child: _PlayerProgress(
                                    duration: duration,
                                    seeking: _seeking,
                                    seekValue: _seekValue,
                                    onDragStart: _beginSeek,
                                    onDragUpdate: _updateSeek,
                                    onSeekEnd: _finishSeek,
                                    onSeekCancel: _cancelSeek,
                                    onTapSeek: _tapSeek,
                                  ),
                                ),
                                _StaggeredFade(
                                  delay: 0.5,
                                  child: _buildControls(
                                    playerService,
                                    isPlaying,
                                    playMode,
                                  ),
                                ),
                                _buildSourceQualityBar(currentMusic),
                                const SizedBox(height: 12),
                              ],
                            ),
                            Column(
                              children: [
                                const Expanded(
                                  child: LyricView(isFullScreen: true),
                                ),
                                _StaggeredFade(
                                  delay: 0.55,
                                  child: _buildLyricMiniBar(
                                    currentMusic,
                                    playerService,
                                    isPlaying,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceQualityBar(MusicItem music) {
    final media = ref.watch(currentMediaItemProvider).value;
    final extras = media?.extras ?? music.toJson();
    final platform = (extras['platform'] ?? music.platform).toString();
    final isLocal =
        extras['local'] == true ||
        extras['source']?.toString() == 'local' ||
        platform == 'local';
    final requested = extras['requestedQuality']?.toString() ?? '320k';
    // 只展示实际播放音质，不用 requestedQuality 冒充
    final actualRaw = extras['actualQuality']?.toString();
    final meta = extras['meta'];
    final localActualRaw =
        extras['localActualQuality']?.toString() ??
        (meta is Map ? meta['localActualQuality']?.toString() : null);
    final remote = extras['remoteUrl']?.toString();
    // 本地音乐无 actualQuality/remoteUrl，但可从 file:// 扩展名推断音质
    // （.flac → 无损、.mp3 → 320k 等），避免一直显示“解析中…”。
    final urlForQuality = (actualRaw != null && actualRaw.isNotEmpty)
        ? null
        : (remote != null && remote.isNotEmpty ? remote : null) ??
              extras['url']?.toString();
    final actual = (actualRaw != null && actualRaw.isNotEmpty)
        ? actualRaw
        : (localActualRaw != null && localActualRaw.isNotEmpty)
        ? localActualRaw
        : (urlForQuality != null && urlForQuality.isNotEmpty
              ? isLocal
                    ? _localFallbackQualityFromUrl(urlForQuality)
                    : correctQualityFromUrl(urlForQuality, requested)
              : null);
    final qualityText = actual != null
        ? qualityLabel(actual)
        : (isLocal ? '未知音质' : '解析中…');
    // 纯透明底，整体下移 10px；点击收起全屏播放器
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Pressable(
        semanticLabel: '收起播放器',
        scale: 0.94,
        onTap: () => Navigator.pop(context),
        child: Text(
          '${platformLabel(platform)} · $qualityText',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.mutedText(context),
            fontSize: 12,
            letterSpacing: 0.5,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  String? _localFallbackQualityFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.flac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ape') ||
        lower.endsWith('.alac') ||
        lower.endsWith('.aiff')) {
      return 'flac';
    }
    return null;
  }

  Widget _buildAppBar(BuildContext context, MusicItem music) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.fill(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder(context)),
            ),
            child: Pressable(
              tooltip: _currentPage == 0 ? '收起播放器' : '返回封面',
              scale: 0.9,
              onTap: () {
                if (_currentPage == 1) {
                  // 从歌词页返回封面页。
                  if (reduceMotion(context)) {
                    _pageController.jumpToPage(0);
                  } else {
                    _pageController.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                    );
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: SizedBox(
                width: 36,
                height: 36,
                child: AnimatedRotation(
                  // 封面页朝下（收起）；歌词页顺时针旋转 90° 朝左（返回封面）。
                  turns: _currentPage == 1 ? 0.25 : 0,
                  duration: motionDuration(
                    context,
                    const Duration(milliseconds: 320),
                  ),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.secondaryText(context),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _currentPage == 0 ? '正在播放' : '歌词',
                style: TextStyle(
                  color: AppColors.mutedText(context),
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              _buildPageIndicator(),
            ],
          ),
          Pressable(
            tooltip: '更多',
            scale: 0.9,
            onTap: () => _showMoreMenu(context, music),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.more_vert,
                color: AppColors.secondaryText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        return AnimatedContainer(
          duration: motionDuration(context, const Duration(milliseconds: 300)),
          margin: EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == index ? 12 : 6,
          height: 4,
          decoration: BoxDecoration(
            color: _currentPage == index
                ? AppColors.accentOf(context)
                : AppColors.mutedText(context).withAlpha(100),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildArtwork(String? artwork, {String? songId}) {
    // 与歌名行同宽：左右 32，对齐歌名左侧到心形右侧区域
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth - 64).clamp(240.0, 420.0);
        final box = side.clamp(0.0, constraints.maxHeight - 8);
        return Center(
          child: Pressable(
            semanticLabel: '打开歌词',
            onTap: _openLyricsPage,
            child: Container(
              width: box,
              height: box,
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: AnimatedSwitcher(
                  duration: motionDuration(
                    context,
                    kFullPlayerTrackSwitchDuration,
                  ),
                  reverseDuration: motionDuration(
                    context,
                    kFullPlayerTrackSwitchReverseDuration,
                  ),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  transitionBuilder: (child, animation) {
                    final scale = Tween<double>(begin: 0.92, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: scale, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<String>(songId ?? artwork ?? 'empty'),
                    child: artwork != null && artwork.isNotEmpty
                        ? ArtworkImage(
                            artwork,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _defaultArtwork(),
                          )
                        : _defaultArtwork(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _defaultArtwork() {
    return Container(
      color: AppColors.cardAlt(context),
      child: Icon(
        Icons.music_note,
        color: AppColors.mutedText(context),
        size: 80,
      ),
    );
  }

  Widget _buildSongInfo(MusicItem music) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: motionDuration(context, kFullPlayerTrackSwitchDuration),
              reverseDuration: motionDuration(
                context,
                kFullPlayerTrackSwitchReverseDuration,
              ),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final offset =
                    Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: Column(
                key: ValueKey<String>(music.identityKey),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    music.name,
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    music.singer,
                    style: TextStyle(
                      color: AppColors.secondaryText(context),
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Pressable(
            tooltip: '下载',
            scale: 0.9,
            onTap: () async {
              try {
                await ref.read(downloadSongProvider)(music);
                if (!mounted) return;
                showAppNotification(
                  '已添加到下载队列',
                  type: AppNotificationType.success,
                );
              } catch (_) {
                if (!mounted) return;
                showAppNotification('添加下载失败', type: AppNotificationType.error);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.download,
                color: AppColors.secondaryText(context),
                size: 24,
              ),
            ),
          ),
          FavoriteButton(
            song: music,
            iconSize: 28,
            activeColor: AppColors.error,
          ),
        ],
      ),
    );
  }

  /// 点击封面切换到全屏歌词页。
  void _openLyricsPage() {
    if (reduceMotion(context)) {
      _pageController.jumpToPage(1);
    } else {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 全屏歌词页底部简约栏：歌名/歌手两行 | 播放键（整体下移 10px）
  Widget _buildLyricMiniBar(
    MusicItem music,
    PlayerService playerService,
    bool isPlaying,
  ) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 20, 16), // 整体下移 10px
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 歌词页关闭动效只保留播放按钮飞行，歌名不参与。
                      Text(
                        music.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.onScaffold(context),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        music.singer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.secondaryText(context),
                          fontSize: 15,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                PlayPulseButton(
                  isPlaying: isPlaying,
                  onPressed: playerService.togglePlay,
                  size: 64,
                  iconSize: 34,
                ),
              ],
            ),
          ),
          // 底部居中的低调关闭按钮：宽箭头、位置比播放键略低、不抢视觉。
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Pressable(
              semanticLabel: '收起播放器',
              scale: 0.92,
              onTap: () => Navigator.pop(context),
              child: Icon(
                Icons.keyboard_arrow_down,
                color: AppColors.mutedText(context),
                size: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _beginSeek(double value) {
    final playing = ref.read(playbackStateProvider).value?.playing ?? false;
    setState(() {
      _seeking = true;
      _wasPlayingBeforeSeek = playing;
      _seekValue = value;
    });
    _dragOperation = _scrubSession.begin();
  }

  void _updateSeek(double value) {
    setState(() => _seekValue = value);
  }

  Future<void> _finishSeek(Duration target) async {
    final operation = _dragOperation;
    if (operation == null) return;
    final mayClear = await _scrubSession.finish(
      operation,
      target,
      resumeAfter: _wasPlayingBeforeSeek,
    );
    if (mounted && mayClear) {
      if (identical(_dragOperation, operation)) {
        _dragOperation = null;
      }
      setState(() => _seeking = false);
    }
  }

  void _cancelSeek() {
    _cancelActiveScrub();
    if (mounted) setState(() {});
  }

  Future<void> _tapSeek(double value, Duration target) async {
    final playing = ref.read(playbackStateProvider).value?.playing ?? false;
    setState(() {
      _seekValue = value;
      _seeking = true;
      _wasPlayingBeforeSeek = playing;
    });
    final operation = _scrubSession.begin();
    final mayClear = await _scrubSession.finish(
      operation,
      target,
      resumeAfter: playing,
    );
    if (mounted && mayClear) {
      setState(() => _seeking = false);
    }
  }

  Widget _buildControls(
    PlayerService playerService,
    bool isPlaying,
    PlayMode playMode,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Pressable(
            tooltip: '播放模式',
            scale: 0.9,
            onTap: () {
              final nextMode = _getNextPlayMode(playMode);
              _applyPlayMode(playerService, nextMode);
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: AnimatedSwitcher(
                duration: motionDuration(
                  context,
                  const Duration(milliseconds: 300),
                ),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  _getPlayModeIcon(playMode),
                  key: ValueKey(playMode),
                  color: AppColors.mutedText(context),
                  size: 22,
                ),
              ),
            ),
          ),
          Pressable(
            semanticLabel: '上一首',
            onTap: playerService.previous,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.skip_previous,
                color: AppColors.onScaffold(context),
                size: 32,
              ),
            ),
          ),
          PlayPulseButton(
            isPlaying: isPlaying,
            onPressed: playerService.togglePlay,
            size: 64,
            iconSize: 34,
          ),
          Pressable(
            semanticLabel: '下一首',
            onTap: playerService.next,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.skip_next,
                color: AppColors.onScaffold(context),
                size: 32,
              ),
            ),
          ),
          Pressable(
            tooltip: '播放队列',
            scale: 0.9,
            onTap: () => _showPlaylist(context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.queue_music,
                color: AppColors.mutedText(context),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PlayMode _getNextPlayMode(PlayMode current) {
    switch (current) {
      case PlayMode.repeatOne:
        return PlayMode.sequential;
      case PlayMode.sequential:
        return PlayMode.shuffle;
      case PlayMode.shuffle:
        return PlayMode.repeatOne;
    }
  }

  IconData _getPlayModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.repeatOne:
        return Icons.repeat_one;
      case PlayMode.sequential:
        return Icons.trending_flat;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  void _applyPlayMode(PlayerService playerService, PlayMode mode) {
    switch (mode) {
      case PlayMode.repeatOne:
        playerService.setRepeatMode(AudioServiceRepeatMode.one);
        playerService.setShuffleMode(false);
        break;
      case PlayMode.sequential:
        playerService.setRepeatMode(AudioServiceRepeatMode.none);
        playerService.setShuffleMode(false);
        break;
      case PlayMode.shuffle:
        playerService.setRepeatMode(AudioServiceRepeatMode.none);
        playerService.setShuffleMode(true);
        break;
    }
  }

  void _showPlaylist(BuildContext context) {
    final playerService = ref.read(playerServiceProvider);
    final queue = playerService.queue;
    final currentIndex = playerService.currentIndex;

    showKoyzeSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final itemCount = playerService.currentLazyPlaylistSongCount > 0
            ? playerService.currentLazyPlaylistSongCount
            : queue.length;
        final sheetSize = _playbackQueueSheetInitialSize(context, itemCount);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: sheetSize,
          minChildSize: 0.18,
          maxChildSize: sheetSize,
          snap: true,
          builder: (context, scrollController) => Material(
            color: AppColors.dialogBg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: _PlaybackQueueSheet(
              queue: queue,
              currentIndex: currentIndex,
              playerService: playerService,
              lazyPlaylistId: playerService.currentLazyPlaylistId,
              dragScrollController: scrollController,
            ),
          ),
        );
      },
    );
  }

  void _showMoreMenu(BuildContext context, MusicItem music) {
    final pageContext = context;
    showKoyzeSheet(
      context: context,
      backgroundColor: AppColors.dialogBg(context),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              margin: EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.mutedText(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.fill(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          music.name,
                          style: TextStyle(
                            color: AppColors.onScaffold(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          music.singer,
                          style: TextStyle(
                            color: AppColors.mutedText(context),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: AppColors.cardBorder(context), height: 1),
            ListTile(
              leading: Icon(
                Icons.favorite_border,
                color: AppColors.onScaffold(context),
              ),
              title: Text(
                '收藏',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(toggleFavoriteProvider)(music);
                } catch (error) {
                  if (!mounted) return;
                  showAppNotification(
                    '收藏失败: $error',
                    type: AppNotificationType.error,
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.thumb_down_alt_outlined,
                color: AppColors.onScaffold(context),
              ),
              title: Text(
                '不喜欢并跳过',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref
                      .read(ratingServiceProvider)
                      .set(music.identityKey, PlayerService.dislikedRating);
                  await ref.read(playerServiceProvider).next();
                  if (!mounted) return;
                  showAppNotification(
                    '已标记不喜欢，后续播放会自动跳过',
                    type: AppNotificationType.success,
                  );
                } catch (error) {
                  if (!mounted) return;
                  showAppNotification(
                    '标记不喜欢失败: $error',
                    type: AppNotificationType.error,
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.playlist_add,
                color: AppColors.onScaffold(context),
              ),
              title: Text(
                '添加到歌单',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              onTap: () {
                Navigator.pop(context);
                showPlaylistPicker(context: pageContext, ref: ref, song: music);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.download,
                color: AppColors.onScaffold(context),
              ),
              title: Text(
                '下载',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(downloadSongProvider)(music);
                  if (!mounted) return;
                  showAppNotification(
                    '已添加到下载队列',
                    type: AppNotificationType.success,
                  );
                } catch (_) {
                  if (!mounted) return;
                  showAppNotification(
                    '添加下载失败',
                    type: AppNotificationType.error,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackQueueSheet extends ConsumerStatefulWidget {
  const _PlaybackQueueSheet({
    required this.queue,
    required this.currentIndex,
    required this.playerService,
    required this.dragScrollController,
    this.lazyPlaylistId,
  });

  final List<MediaItem> queue;
  final int currentIndex;
  final PlayerService playerService;
  final ScrollController dragScrollController;

  /// 惰性分页歌单 ID；非空时展示完整歌单的分页列表。
  final String? lazyPlaylistId;

  @override
  ConsumerState<_PlaybackQueueSheet> createState() =>
      _PlaybackQueueSheetState();
}

class _PlaybackQueueSheetState extends ConsumerState<_PlaybackQueueSheet> {
  static const double _queueTileHeight = 56.0;

  late int _pageIndex;
  ScrollController get _queueScrollController => widget.dragScrollController;
  int? _focusedPageForScroll;
  PlaylistSongPage? _displayedPage;
  int? _displayedPageIndex;

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.lazyPlaylistId != null
        ? PageRange.pageForItem(index: _lazyCurrentIndex())
        : PageRange.pageForItem(
            index: widget.currentIndex >= 0 ? widget.currentIndex : 0,
          );
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _wrapQueueScrollable(Widget child) => child;

  int _lazyCurrentIndex() {
    final current = widget.playerService.mediaItem?.extras;
    final lazyIndex = current?['_lazyPlaylistIndex'];
    if (lazyIndex is int) return lazyIndex;
    return widget.currentIndex >= 0 ? widget.currentIndex : 0;
  }

  void _scrollToCurrentIfNeeded(
    int pageIndex,
    int currentIndex,
    int pageStart,
  ) {
    if (currentIndex < pageStart || _focusedPageForScroll == pageIndex) return;
    final offsetInPage = currentIndex - pageStart;
    _focusedPageForScroll = pageIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_queueScrollController.hasClients) {
        _focusedPageForScroll = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_queueScrollController.hasClients) return;
          final position = _queueScrollController.position;
          final target =
              (offsetInPage * _queueTileHeight -
                      (position.viewportDimension - _queueTileHeight) / 2)
                  .clamp(0.0, position.maxScrollExtent);
          if (reduceMotion(context)) {
            _queueScrollController.jumpTo(target);
          } else {
            _queueScrollController.animateTo(
              target,
              duration: kFullPlayerTrackSwitchReverseDuration,
              curve: Curves.easeOutCubic,
            );
          }
        });
        return;
      }
      final position = _queueScrollController.position;
      final target =
          (offsetInPage * _queueTileHeight -
                  (position.viewportDimension - _queueTileHeight) / 2)
              .clamp(0.0, position.maxScrollExtent);
      if (reduceMotion(context)) {
        _queueScrollController.jumpTo(target);
      } else {
        _queueScrollController.animateTo(
          target,
          duration: kFullPlayerTrackSwitchReverseDuration,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _playAt(int globalIndex) async {
    final playlistId = widget.lazyPlaylistId;
    if (playlistId == null) {
      await widget.playerService.setQueue(
        widget.queue.map((e) => MusicItem.fromJson(e.extras ?? {})).toList(),
        startIndex: globalIndex,
        manualPlayName: globalIndex >= 0 && globalIndex < widget.queue.length
            ? widget.queue[globalIndex].title
            : null,
      );
      return;
    }
    await widget.playerService.playPagedPlaylist(
      songCount: widget.playerService.currentLazyPlaylistSongCount > 0
          ? widget.playerService.currentLazyPlaylistSongCount
          : widget.queue.length,
      startIndex: globalIndex,
      playlistId: playlistId,
      manual: true,
      loadPage: (offset, limit) async {
        final page = await ref
            .read(playlistServiceProvider)
            .getSongsPage(playlistId, offset: offset, limit: limit);
        return page.songs;
      },
    );
  }

  Widget _buildLazyPage(
    BuildContext context, {
    required PlaylistSongPage page,
    required int pageStart,
    required PageRange range,
    required int currentIndex,
    required bool loading,
  }) {
    final queueItems = page.songs;
    // 页面级一次性读取收藏集合，避免滚动时每行创建异步查询。
    final favoriteIds =
        ref.watch(favoriteIdsProvider).valueOrNull ?? const <String>{};
    _scrollToCurrentIfNeeded(
      _displayedPageIndex ?? range.pageIndex,
      currentIndex,
      pageStart,
    );
    return Expanded(
      child: Stack(
        children: [
          Positioned.fill(
            child: _wrapQueueScrollable(
              ListView.builder(
                controller: _queueScrollController,
                itemCount: queueItems.length,
                itemExtent: _queueTileHeight,
                padding: EdgeInsets.only(
                  bottom: range.pageCount > 1
                      ? PageNavigationBar.listBottomPadding
                      : 0,
                ),
                itemBuilder: (context, index) {
                  final item = queueItems[index];
                  final globalIndex = pageStart + index;
                  final isPlaying = globalIndex == currentIndex;
                  return ListTile(
                    dense: true,
                    minTileHeight: _queueTileHeight,
                    leading: isPlaying
                        ? Icon(
                            Icons.play_arrow,
                            color: AppColors.accentOf(context),
                          )
                        : Text(
                            '${globalIndex + 1}',
                            style: TextStyle(
                              color: AppColors.mutedText(context),
                              fontSize: 14,
                            ),
                          ),
                    title: Text(
                      item.name,
                      style: TextStyle(
                        color: isPlaying
                            ? AppColors.accentOf(context)
                            : AppColors.onScaffold(context),
                        fontSize: 14,
                        fontWeight: isPlaying
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.singer,
                      style: TextStyle(
                        color: AppColors.mutedText(context),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: FavoriteButton(
                      song: item,
                      isFavorite: favoriteIds.contains(item.identityKey),
                    ),
                    onTap: loading
                        ? null
                        : () async {
                            await _playAt(globalIndex);
                            if (context.mounted) Navigator.pop(context);
                          },
                  );
                },
              ),
            ),
          ),
          if (loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PageNavigationBar(
              pageIndex: range.pageIndex,
              pageCount: range.pageCount,
              enabled: !loading,
              onPageChanged: (pageIndex) {
                _focusedPageForScroll = null;
                setState(() => _pageIndex = pageIndex);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlistId = widget.lazyPlaylistId;
    final currentIndex = playlistId != null
        ? _lazyCurrentIndex()
        : widget.currentIndex;

    if (playlistId != null) {
      final lazySongCount = widget.playerService.currentLazyPlaylistSongCount;
      final range = PageRange(
        itemCount: lazySongCount > 0 ? lazySongCount : widget.queue.length,
        pageIndex: _pageIndex,
      );
      final songsPage = ref.watch(
        playlistSongsPageProvider(
          PlaylistSongsPageRequest(
            playlistId: playlistId,
            pageIndex: range.pageIndex,
          ),
        ),
      );

      return SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.mutedText(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.queue_music,
                    color: AppColors.accentOf(context),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '播放列表 (${range.itemCount})',
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: AppColors.cardBorder(context), height: 1),
            songsPage.when(
              skipLoadingOnRefresh: true,
              loading: () {
                final page = _displayedPage;
                if (page == null) {
                  return const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final displayedIndex = _displayedPageIndex ?? range.pageIndex;
                return _buildLazyPage(
                  context,
                  page: page,
                  pageStart: displayedIndex * PageRange.defaultPageSize,
                  range: range,
                  currentIndex: currentIndex,
                  loading: true,
                );
              },
              error: (error, stackTrace) => Expanded(
                child: Center(
                  child: Text(
                    '完整列表加载失败，显示当前队列',
                    style: TextStyle(color: AppColors.mutedText(context)),
                  ),
                ),
              ),
              data: (page) {
                if (page.songs.isEmpty) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        '播放列表为空',
                        style: TextStyle(color: AppColors.mutedText(context)),
                      ),
                    ),
                  );
                }
                _displayedPage = page;
                _displayedPageIndex = range.pageIndex;
                return _buildLazyPage(
                  context,
                  page: page,
                  pageStart: range.start,
                  range: range,
                  currentIndex: currentIndex,
                  loading: false,
                );
              },
            ),
          ],
        ),
      );
    }

    return _buildShortQueue(context, currentIndex);
  }

  Widget _buildShortQueue(
    BuildContext context,
    int currentIndex, {
    String? fallbackReason,
  }) {
    final range = PageRange(
      itemCount: widget.queue.length,
      pageIndex: _pageIndex,
    );
    final queue = pageSlice(widget.queue, range);
    _scrollToCurrentIfNeeded(range.pageIndex, currentIndex, range.start);
    final hasMultiplePages = range.pageCount > 1;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.mutedText(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.queue_music,
                  color: AppColors.accentOf(context),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '播放列表 (${widget.queue.length})',
                  style: TextStyle(
                    color: AppColors.onScaffold(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: AppColors.cardBorder(context), height: 1),
          if (widget.queue.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                fallbackReason == null ? '播放列表为空' : '完整列表加载失败，显示当前队列',
                style: TextStyle(
                  color: AppColors.mutedText(context),
                  fontSize: 14,
                ),
              ),
            )
          else
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _wrapQueueScrollable(
                      ListView.builder(
                        controller: _queueScrollController,
                        itemCount: queue.length,
                        itemExtent: _queueTileHeight,
                        padding: EdgeInsets.only(
                          bottom: range.pageCount > 1
                              ? PageNavigationBar.listBottomPadding
                              : 0,
                        ),
                        itemBuilder: (context, index) {
                          final item = queue[index];
                          final queueIndex = range.start + index;
                          final isPlaying = queueIndex == currentIndex;
                          return ListTile(
                            dense: true,
                            minTileHeight: _queueTileHeight,
                            leading: isPlaying
                                ? Icon(
                                    Icons.play_arrow,
                                    color: AppColors.accentOf(context),
                                  )
                                : Text(
                                    '${queueIndex + 1}',
                                    style: TextStyle(
                                      color: AppColors.mutedText(context),
                                      fontSize: 14,
                                    ),
                                  ),
                            title: Text(
                              item.title,
                              style: TextStyle(
                                color: isPlaying
                                    ? AppColors.accentOf(context)
                                    : AppColors.onScaffold(context),
                                fontSize: 14,
                                fontWeight: isPlaying
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item.artist ?? '',
                              style: TextStyle(
                                color: AppColors.mutedText(context),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () async {
                              await _playAt(queueIndex);
                              if (context.mounted) Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  if (hasMultiplePages)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: PageNavigationBar(
                        pageIndex: range.pageIndex,
                        pageCount: range.pageCount,
                        onPageChanged: (pageIndex) {
                          _focusedPageForScroll = null;
                          setState(() => _pageIndex = pageIndex);
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 播放器展开动画中的交错淡入：progress 超过 [delay] 后开始淡入。
/// 封面/歌名/歌词/进度/按钮各自延迟，形成"各元素有自己的动作"的层次感。
class _StaggeredFade extends StatelessWidget {
  const _StaggeredFade({required this.delay, required this.child});

  /// 淡入开始的进度阈值（0~1）。
  final double delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: playerRouteProgress,
      builder: (context, progress, _) {
        final t = delay >= 1
            ? 1.0
            : ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
        return Opacity(
          opacity: Curves.easeOutCubic.transform(t),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - Curves.easeOutCubic.transform(t))),
            child: child,
          ),
        );
      },
    );
  }
}
