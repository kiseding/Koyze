import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../../search/presentation/search_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';

class SongListDetailScreen extends ConsumerStatefulWidget {
  final MusicItem songList;
  const SongListDetailScreen({super.key, required this.songList});

  @override
  ConsumerState<SongListDetailScreen> createState() =>
      _SongListDetailScreenState();
}

class _SongListDetailScreenState extends ConsumerState<SongListDetailScreen> {
  final List<MusicItem> _songs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _songs.clear();
    });
    try {
      final musicSourceService = ref.read(musicSourceServiceProvider);
      final platform = widget.songList.platform.isNotEmpty
          ? widget.songList.platform
          : widget.songList.source;
      final songs = await musicSourceService.getSongListDetail(
        platform,
        widget.songList.id,
      );
      if (mounted) {
        setState(() {
          _songs.addAll(songs);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 列表可滚动到栏内部（栏高度不变），顶栏渐变才有可见过渡。
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          // 顶栏背景在栏内部渐变：顶部实色 → 底部 100% 透明。
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          title: Text(
            widget.songList.name,
            style: TextStyle(
              color: AppColors.onScaffold(context),
              fontSize: 18,
            ),
          ),
          leading: FxIconButton(
            tooltip: '返回',
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (_songs.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  final playerService = ref.read(playerServiceProvider);
                  playerService.setQueue(
                    _songs,
                    startIndex: 0,
                    manualPlayName: _songs.first.name,
                  );
                },
                icon: Icon(
                  Icons.play_arrow,
                  color: AppColors.accentOf(context),
                  size: 20,
                ),
                label: Text(
                  '播放全部',
                  style: TextStyle(
                    color: AppColors.accentOf(context),
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
        body: _isLoading
            ? Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accentOf(context),
                  ),
                ),
              )
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '加载失败: $_error',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _loadDetail,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              )
            : _songs.isEmpty
            ? Center(
                child: Text(
                  '歌单为空',
                  style: TextStyle(color: AppColors.mutedText(context)),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                  bottom: 16,
                  left: 16,
                  right: 16,
                ),
                itemCount: _songs.length,
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  return _SongListRow(
                    song: song,
                    index: index,
                    onTap: () {
                      final playerService = ref.read(playerServiceProvider);
                      playerService.setQueue(
                        _songs,
                        startIndex: index,
                        manualPlayName: song.name,
                      );
                    },
                    placeholder: _placeholder,
                  );
                },
              ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 40,
      height: 40,
      color: AppColors.cardAlt(context),
      child: Icon(
        Icons.music_note,
        color: AppColors.secondaryText(context),
        size: 20,
      ),
    );
  }
}

class _SongListRow extends ConsumerWidget {
  const _SongListRow({
    required this.song,
    required this.index,
    required this.onTap,
    required this.placeholder,
  });

  final MusicItem song;
  final int index;
  final VoidCallback onTap;
  final Widget Function() placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(
      currentMusicProvider.select(
        (current) => current?.identityKey == song.identityKey,
      ),
    );
    final accent = AppColors.accentOf(context);

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.fill(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: isPlaying
                    ? Icon(Icons.play_arrow, size: 22, color: accent)
                    : Text(
                        '${index + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.secondaryText(context),
                          fontSize: 13,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: song.artwork != null && song.artwork!.isNotEmpty
                    ? ArtworkImage(
                        song.artwork!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => placeholder(),
                      )
                    : placeholder(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.name,
                      style: TextStyle(
                        color: isPlaying
                            ? accent
                            : AppColors.onScaffold(context),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${song.singer} · ${song.album}',
                      style: TextStyle(
                        color: AppColors.secondaryText(context),
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
      ),
    );
  }
}
