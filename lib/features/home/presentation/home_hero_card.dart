import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/micro_animations.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/pressable.dart';
import '../../nas/domain/nas_kind.dart';
import '../../nas/presentation/nas_provider.dart';
import '../../player/domain/music_item.dart';
import '../../player/domain/player_service.dart';
import '../../player/presentation/player_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../recommend/presentation/recommendation_provider.dart';
import '../../subsonic/presentation/subsonic_provider.dart';

/// 首页大卡片：对应歌单 tab 顶部那五张，同一时间只能启用一张。
enum HomeHeroCardId { favorites, recommend, local, nas, recent }

extension HomeHeroCardIdX on HomeHeroCardId {
  static HomeHeroCardId? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final value in HomeHeroCardId.values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

class HomeHeroCardOption {
  const HomeHeroCardOption({
    required this.id,
    required this.title,
    required this.icon,
    this.color,
  });

  final HomeHeroCardId id;
  final String title;
  final IconData icon;
  final Color? color;

  Color colorOf(BuildContext context) => color ?? AppColors.accentOf(context);
}

const homeHeroCardOptions = <HomeHeroCardOption>[
  HomeHeroCardOption(
    id: HomeHeroCardId.favorites,
    title: '收藏列表',
    icon: Icons.favorite,
  ),
  HomeHeroCardOption(
    id: HomeHeroCardId.recommend,
    title: '猜你喜欢',
    icon: Icons.auto_awesome,
    color: Color(0xFFFF8F1F),
  ),
  HomeHeroCardOption(
    id: HomeHeroCardId.local,
    title: '本地音乐',
    icon: Icons.library_music,
    color: Colors.purple,
  ),
  HomeHeroCardOption(
    id: HomeHeroCardId.nas,
    title: 'NAS 乐库',
    icon: Icons.cloud_queue_rounded,
    color: Colors.pink,
  ),
  HomeHeroCardOption(
    id: HomeHeroCardId.recent,
    title: '最近播放',
    icon: Icons.history_rounded,
    color: Colors.blue,
  ),
];

final homeHeroCardProvider =
    StateNotifierProvider<HomeHeroCardNotifier, HomeHeroCardId>(
      (ref) => HomeHeroCardNotifier(),
    );

class HomeHeroCardNotifier extends StateNotifier<HomeHeroCardId> {
  HomeHeroCardNotifier({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance),
      super(HomeHeroCardId.favorites) {
    _load();
  }

  static const _key = 'home_hero_card_v1';
  final StorageLoader _storage;
  int _generation = 0;

  Future<void> _load() async {
    try {
      final parsed = HomeHeroCardIdX.tryParse(
        (await _storage()).getString(_key),
      );
      if (parsed != null && parsed != state) state = parsed;
    } catch (_) {}
  }

  void select(HomeHeroCardId id) {
    if (state == id) return;
    state = id;
    _persist();
  }

  Future<void> _persist() async {
    final generation = ++_generation;
    try {
      final storage = await _storage();
      if (generation != _generation) return;
      await storage.setString(_key, state.name);
    } catch (_) {}
  }
}

/// 首页大卡片右侧按钮的播放方式（与播放页全局模式独立）。
enum HomeHeroPlayMode { sequential, shuffle, repeatOne }

extension HomeHeroPlayModeX on HomeHeroPlayMode {
  static HomeHeroPlayMode? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final value in HomeHeroPlayMode.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  String get title => switch (this) {
    HomeHeroPlayMode.sequential => '顺序播放',
    HomeHeroPlayMode.shuffle => '随机播放',
    HomeHeroPlayMode.repeatOne => '单曲循环',
  };

  String get caption => switch (this) {
    HomeHeroPlayMode.sequential => '按列表顺序播放，播完回到第一首',
    HomeHeroPlayMode.shuffle => '打乱顺序，播完继续随机下一首',
    HomeHeroPlayMode.repeatOne => '只循环当前第一首',
  };

  IconData get icon => switch (this) {
    HomeHeroPlayMode.sequential => Icons.repeat,
    HomeHeroPlayMode.shuffle => Icons.shuffle,
    HomeHeroPlayMode.repeatOne => Icons.repeat_one,
  };
}

final homeHeroPlayModeProvider =
    StateNotifierProvider<HomeHeroPlayModeNotifier, HomeHeroPlayMode>(
      (ref) => HomeHeroPlayModeNotifier(),
    );

class HomeHeroPlayModeNotifier extends StateNotifier<HomeHeroPlayMode> {
  HomeHeroPlayModeNotifier({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance),
      super(HomeHeroPlayMode.shuffle) {
    _load();
  }

  static const _key = 'home_hero_play_mode_v1';
  final StorageLoader _storage;
  int _generation = 0;

  Future<void> _load() async {
    try {
      final parsed = HomeHeroPlayModeX.tryParse(
        (await _storage()).getString(_key),
      );
      if (parsed != null && parsed != state) state = parsed;
    } catch (_) {}
  }

  void select(HomeHeroPlayMode mode) {
    if (state == mode) return;
    state = mode;
    _persist();
  }

  Future<void> _persist() async {
    final generation = ++_generation;
    try {
      final storage = await _storage();
      if (generation != _generation) return;
      await storage.setString(_key, state.name);
    } catch (_) {}
  }
}

/// 首页右上角「首页大卡片设置」弹层：选卡片 + 选播放模式。
class HomeHeroCardSettings extends ConsumerWidget {
  const HomeHeroCardSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(homeHeroCardProvider);
    final playMode = ref.watch(homeHeroPlayModeProvider);
    final onSurface = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            '对应歌单页顶部五张卡片，只能启用其中一张',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: RadioGroup<HomeHeroCardId>(
            groupValue: selected,
            onChanged: (value) {
              if (value != null) {
                ref.read(homeHeroCardProvider.notifier).select(value);
              }
            },
            child: Column(
              children: [
                for (final spec in homeHeroCardOptions)
                  ListTile(
                    visualDensity: VisualDensity.compact,
                    selected: selected == spec.id,
                    leading: Icon(
                      spec.icon,
                      color: spec.colorOf(context),
                      size: 22,
                    ),
                    title: Text(
                      spec.title,
                      style: TextStyle(
                        color: selected == spec.id ? onSurface : muted,
                        fontSize: 15,
                        fontWeight: selected == spec.id
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: Radio<HomeHeroCardId>(value: spec.id),
                    onTap: () =>
                        ref.read(homeHeroCardProvider.notifier).select(spec.id),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            '右侧按钮播放模式',
            style: TextStyle(
              color: onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            '只影响首页大卡片右侧按钮，和播放页模式互不影响',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: RadioGroup<HomeHeroPlayMode>(
            groupValue: playMode,
            onChanged: (value) {
              if (value != null) {
                ref.read(homeHeroPlayModeProvider.notifier).select(value);
              }
            },
            child: Column(
              children: [
                for (final mode in HomeHeroPlayMode.values)
                  ListTile(
                    visualDensity: VisualDensity.compact,
                    selected: playMode == mode,
                    leading: Icon(mode.icon, color: onSurface, size: 22),
                    title: Text(
                      mode.title,
                      style: TextStyle(
                        color: playMode == mode ? onSurface : muted,
                        fontSize: 15,
                        fontWeight: playMode == mode
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      mode.caption,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    trailing: Radio<HomeHeroPlayMode>(value: mode),
                    onTap: () => ref
                        .read(homeHeroPlayModeProvider.notifier)
                        .select(mode),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 首页那张大卡片：外观跟现在的收藏卡一致，内容随所选歌单卡切换。
class HomeHeroCard extends ConsumerWidget {
  const HomeHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(homeHeroCardProvider);
    final spec = homeHeroCardOptions.firstWhere((item) => item.id == id);
    final playMode = ref.watch(homeHeroPlayModeProvider);
    final model = _resolve(context, ref, spec, playMode);
    const onAccent = Colors.white;
    final color = model.color;

    return HoverFloat(
      child: Pressable(
        borderRadius: BorderRadius.circular(18),
        captureExpandRect: true,
        semanticLabel: spec.title,
        onTap: model.onOpen,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withAlpha(230), color.withAlpha(120)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(50),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: onAccent.withAlpha(36),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(spec.icon, color: onAccent, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          spec.title,
                          style: const TextStyle(
                            color: onAccent,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (model.showCountInTitle && model.count > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(${model.count})',
                            style: TextStyle(
                              color: onAccent.withAlpha(210),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      model.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onAccent.withAlpha(210),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Pressable(
                scale: 0.9,
                semanticLabel: model.actionLabel,
                onTap: model.canPlay ? model.onPlay : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: onAccent.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(model.actionIcon, color: onAccent, size: 26),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _HeroModel _resolve(
    BuildContext context,
    WidgetRef ref,
    HomeHeroCardOption spec,
    HomeHeroPlayMode playMode,
  ) {
    final color = spec.colorOf(context);
    final playlists = ref.watch(playlistsProvider);
    final actionIcon = playMode.icon;

    switch (spec.id) {
      case HomeHeroCardId.favorites:
        final count =
            playlists
                .where((playlist) => playlist.id == 'favorites')
                .firstOrNull
                ?.songCount ??
            0;
        return _HeroModel(
          color: color,
          subtitle: count == 0 ? '还没有收藏歌曲' : '点击查看，右侧${playMode.title}',
          count: count,
          canPlay: count > 0,
          actionIcon: actionIcon,
          actionLabel: '${playMode.title}收藏',
          onOpen: () => context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'favorites'},
          ),
          onPlay: () => _playFavorites(context, ref, playMode),
        );
      case HomeHeroCardId.recommend:
        final recommendations =
            ref.watch(recommendationProvider).valueOrNull ?? const [];
        final count = recommendations.length;
        return _HeroModel(
          color: color,
          subtitle: count > 0 ? '为你推荐 $count 首歌曲' : '收藏歌曲后为你推荐',
          count: count,
          canPlay: count > 0,
          actionIcon: actionIcon,
          actionLabel: '${playMode.title}猜你喜欢',
          onOpen: () => context.push('/recommend'),
          onPlay: () => _playRecommend(
            context,
            ref,
            recommendations.map((item) => item.song).toList(),
            playMode,
          ),
        );
      case HomeHeroCardId.local:
        final count =
            playlists
                .where((playlist) => playlist.id == 'local')
                .firstOrNull
                ?.songCount ??
            0;
        return _HeroModel(
          color: color,
          subtitle: count == 0 ? '选择文件夹扫描设备歌曲' : '$count 首歌曲',
          count: count,
          canPlay: count > 0,
          actionIcon: actionIcon,
          actionLabel: '${playMode.title}本地音乐',
          onOpen: () => context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'local'},
          ),
          onPlay: () => _playPaged(context, ref, 'local', count, playMode),
        );
      case HomeHeroCardId.nas:
        final subsonicConnected = ref.watch(subsonicConnectedProvider);
        final nasConnected = {
          for (final kind in NasKind.values)
            kind: ref.watch(nasConnectedProvider(kind)),
        };
        final connected =
            subsonicConnected || nasConnected.values.any((value) => value);
        final songsAsync = subsonicConnected
            ? ref.watch(subsonicLibrarySongsProvider)
            : const AsyncValue<List<MusicItem>>.data([]);
        final songs = songsAsync.valueOrNull ?? const <MusicItem>[];
        final count = songs.length;
        final config = ref.watch(subsonicConfigProvider);
        final subtitle = !connected
            ? 'Navidrome / Emby / Plex / 群晖'
            : subsonicConnected && songsAsync.isLoading
            ? '正在加载 ${config.hostLabel}'
            : 'NAS';
        return _HeroModel(
          color: color,
          subtitle: subtitle,
          count: count,
          showCountInTitle: false,
          canPlay: subsonicConnected && count > 0,
          actionIcon: actionIcon,
          actionLabel: '${playMode.title} NAS 乐库',
          onOpen: () => context.push('/subsonic'),
          onPlay: () => _playNas(context, ref, songs, playMode),
        );
      case HomeHeroCardId.recent:
        final count =
            playlists
                .where((playlist) => playlist.id == 'recent')
                .firstOrNull
                ?.songCount ??
            0;
        return _HeroModel(
          color: color,
          subtitle: '$count 首歌曲',
          count: count,
          canPlay: count > 0,
          actionIcon: actionIcon,
          actionLabel: '${playMode.title}最近播放',
          onOpen: () => context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'recent'},
          ),
          onPlay: () => _playPaged(context, ref, 'recent', count, playMode),
        );
    }
  }

  Future<void> _applyPlayMode(
    PlayerService player,
    HomeHeroPlayMode mode,
  ) async {
    switch (mode) {
      case HomeHeroPlayMode.sequential:
        await player.setRepeatMode(AudioServiceRepeatMode.none);
        await player.setShuffleMode(false);
      case HomeHeroPlayMode.shuffle:
        await player.setRepeatMode(AudioServiceRepeatMode.none);
        await player.setShuffleMode(true);
      case HomeHeroPlayMode.repeatOne:
        await player.setRepeatMode(AudioServiceRepeatMode.one);
        await player.setShuffleMode(false);
    }
  }

  int _startIndex(HomeHeroPlayMode mode, int count) {
    if (count <= 0) return 0;
    return mode == HomeHeroPlayMode.shuffle ? Random().nextInt(count) : 0;
  }

  Future<void> _playFavorites(
    BuildContext context,
    WidgetRef ref,
    HomeHeroPlayMode mode,
  ) async {
    try {
      final playlistService = ref.read(playlistServiceProvider);
      final favorites = playlistService.favorites;
      if (favorites == null || favorites.songCount <= 0) {
        showAppNotification('还没有收藏歌曲', type: AppNotificationType.info);
        return;
      }
      final songCount = favorites.songCount;
      final playerService = ref.read(playerServiceProvider);
      await _applyPlayMode(playerService, mode);
      await playerService.playPagedPlaylist(
        songCount: songCount,
        startIndex: _startIndex(mode, songCount),
        playlistId: 'favorites',
        manual: true,
        loadPage: (offset, limit) async {
          final page = await playlistService.getSongsPage(
            'favorites',
            offset: offset,
            limit: limit,
          );
          return page.songs;
        },
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppNotification(
        '${mode.title}失败: $error',
        type: AppNotificationType.error,
      );
    }
  }

  Future<void> _playPaged(
    BuildContext context,
    WidgetRef ref,
    String playlistId,
    int songCount,
    HomeHeroPlayMode mode,
  ) async {
    if (songCount <= 0) return;
    try {
      final playlistService = ref.read(playlistServiceProvider);
      final playerService = ref.read(playerServiceProvider);
      await _applyPlayMode(playerService, mode);
      await playerService.playPagedPlaylist(
        songCount: songCount,
        startIndex: _startIndex(mode, songCount),
        playlistId: playlistId,
        manual: true,
        loadPage: (offset, limit) async {
          final page = await playlistService.getSongsPage(
            playlistId,
            offset: offset,
            limit: limit,
          );
          return page.songs;
        },
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppNotification('加载歌曲失败: $error', type: AppNotificationType.error);
    }
  }

  Future<void> _playRecommend(
    BuildContext context,
    WidgetRef ref,
    List<MusicItem> songs,
    HomeHeroPlayMode mode,
  ) async {
    if (songs.isEmpty) return;
    try {
      final playerService = ref.read(playerServiceProvider);
      await _applyPlayMode(playerService, mode);
      final index = _startIndex(mode, songs.length);
      await playerService.playPlaylist(
        songs,
        index: index,
        manualPlayName: songs[index].name,
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppNotification('播放失败: $error', type: AppNotificationType.error);
    }
  }

  Future<void> _playNas(
    BuildContext context,
    WidgetRef ref,
    List<MusicItem> songs,
    HomeHeroPlayMode mode,
  ) async {
    try {
      var queue = songs;
      if (queue.isEmpty) {
        queue = await ref.read(subsonicServiceProvider).getLibrarySongs();
      }
      if (queue.isEmpty) {
        showAppNotification('服务器上还没有歌曲', type: AppNotificationType.info);
        return;
      }
      final playerService = ref.read(playerServiceProvider);
      await _applyPlayMode(playerService, mode);
      final index = _startIndex(mode, queue.length);
      await playerService.playPlaylist(
        queue,
        index: index,
        manualPlayName: queue[index].name,
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppNotification('播放失败: $error', type: AppNotificationType.error);
    }
  }
}

class _HeroModel {
  const _HeroModel({
    required this.color,
    required this.subtitle,
    required this.count,
    required this.canPlay,
    required this.actionIcon,
    required this.actionLabel,
    required this.onOpen,
    required this.onPlay,
    this.showCountInTitle = true,
  });

  final Color color;
  final String subtitle;
  final int count;
  final bool showCountInTitle;
  final bool canPlay;
  final IconData actionIcon;
  final String actionLabel;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
}
