import 'dart:math';

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

/// 首页设置里的大卡片单选。
class HomeHeroCardSettings extends ConsumerWidget {
  const HomeHeroCardSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(homeHeroCardProvider);
    final onSurface = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
          child: Text(
            '首页大卡片',
            style: TextStyle(
              color: onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
        Divider(height: 16, color: AppColors.cardBorder(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Text(
            '快捷功能',
            style: TextStyle(
              color: onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w700,
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
    final model = _resolve(context, ref, spec);
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
  ) {
    final color = spec.colorOf(context);
    final playlists = ref.watch(playlistsProvider);

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
          subtitle: count == 0 ? '还没有收藏歌曲' : '点击查看，右侧随机播放',
          count: count,
          canPlay: count > 0,
          actionIcon: Icons.shuffle,
          actionLabel: '随机播放收藏',
          onOpen: () => context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'favorites'},
          ),
          onPlay: () => _playFavorites(context, ref),
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
          actionIcon: Icons.play_arrow_rounded,
          actionLabel: '播放猜你喜欢',
          onOpen: () => context.push('/recommend'),
          onPlay: () {
            ref
                .read(playerServiceProvider)
                .playPlaylist(
                  recommendations.map((item) => item.song).toList(),
                  manualPlayName: recommendations.first.song.name,
                );
          },
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
          actionIcon: Icons.play_arrow_rounded,
          actionLabel: '播放本地音乐',
          onOpen: () => context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'local'},
          ),
          onPlay: () => _playPaged(context, ref, 'local', count),
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
          actionIcon: Icons.play_arrow_rounded,
          actionLabel: '播放 NAS 乐库',
          onOpen: () => context.push('/subsonic'),
          onPlay: () => _playNas(context, ref, songs),
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
          actionIcon: Icons.play_arrow_rounded,
          actionLabel: '播放最近播放',
          onOpen: () => context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'recent'},
          ),
          onPlay: () => _playPaged(context, ref, 'recent', count),
        );
    }
  }

  Future<void> _playFavorites(BuildContext context, WidgetRef ref) async {
    try {
      final playlistService = ref.read(playlistServiceProvider);
      final favorites = playlistService.favorites;
      if (favorites == null || favorites.songCount <= 0) {
        showAppNotification('还没有收藏歌曲', type: AppNotificationType.info);
        return;
      }
      final songCount = favorites.songCount;
      final playerService = ref.read(playerServiceProvider);
      await playerService.setShuffleMode(true);
      await playerService.playPagedPlaylist(
        songCount: songCount,
        startIndex: Random().nextInt(songCount),
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
      showAppNotification('随机播放失败: $error', type: AppNotificationType.error);
    }
  }

  Future<void> _playPaged(
    BuildContext context,
    WidgetRef ref,
    String playlistId,
    int songCount,
  ) async {
    if (songCount <= 0) return;
    try {
      final playlistService = ref.read(playlistServiceProvider);
      await ref
          .read(playerServiceProvider)
          .playPagedPlaylist(
            songCount: songCount,
            startIndex: 0,
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

  Future<void> _playNas(
    BuildContext context,
    WidgetRef ref,
    List<MusicItem> songs,
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
      await ref
          .read(playerServiceProvider)
          .playPlaylist(queue, manualPlayName: queue.first.name);
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
