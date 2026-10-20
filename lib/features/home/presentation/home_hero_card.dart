import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_strings.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
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
import '../../../core/widgets/origo_chrome.dart';

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

  /// 卡片会从这颜色一路压到近黑，所以起点必须是"深一档"的强调色。
  /// M3 深色主题的 primary 是提亮值（浅蓝），直接用它会把卡片洗成一片灰白；
  /// 深色下改用 primaryContainer，浅色下 primary 本身就是深色，正好对应。
  Color colorOf(BuildContext context) {
    if (color != null) return color!;
    final scheme = Theme.of(context).colorScheme;
    return AppColors.isDark(context) ? scheme.primaryContainer : scheme.primary;
  }

  String titleFor(S s) => switch (id) {
    HomeHeroCardId.favorites => s.favorites,
    HomeHeroCardId.recommend => s.forYou,
    HomeHeroCardId.local => s.localMusic,
    HomeHeroCardId.nas => s.nasLibrary,
    HomeHeroCardId.recent => s.recentPlays,
  };
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

typedef _EnumParser<T extends Enum> = T? Function(String? raw);

class _PersistentEnumNotifier<T extends Enum> extends StateNotifier<T> {
  _PersistentEnumNotifier({
    required T initial,
    required String key,
    required _EnumParser<T> parse,
    StorageLoader? storage,
  }) : _key = key,
       _parse = parse,
       _storage = storage ?? (() => StorageService.instance),
       super(initial) {
    _load();
  }

  final String _key;
  final _EnumParser<T> _parse;
  final StorageLoader _storage;
  int _generation = 0;

  Future<void> _load() async {
    try {
      final parsed = _parse((await _storage()).getString(_key));
      if (parsed != null && parsed != state) state = parsed;
    } catch (_) {}
  }

  void select(T value) {
    if (state == value) return;
    state = value;
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

class HomeHeroCardNotifier extends _PersistentEnumNotifier<HomeHeroCardId> {
  HomeHeroCardNotifier({StorageLoader? storage})
    : super(
        initial: HomeHeroCardId.favorites,
        key: 'home_hero_card_v1',
        parse: HomeHeroCardIdX.tryParse,
        storage: storage,
      );
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

  String titleFor(S s) => switch (this) {
    HomeHeroPlayMode.sequential => s.playInOrder,
    HomeHeroPlayMode.shuffle => s.shufflePlay,
    HomeHeroPlayMode.repeatOne => s.repeatOne,
  };

  String captionFor(S s) => switch (this) {
    HomeHeroPlayMode.sequential => s.playInOrderHint,
    HomeHeroPlayMode.shuffle => s.shufflePlayHint,
    HomeHeroPlayMode.repeatOne => s.repeatOneHint,
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

class HomeHeroPlayModeNotifier
    extends _PersistentEnumNotifier<HomeHeroPlayMode> {
  HomeHeroPlayModeNotifier({StorageLoader? storage})
    : super(
        initial: HomeHeroPlayMode.shuffle,
        key: 'home_hero_play_mode_v1',
        parse: HomeHeroPlayModeX.tryParse,
        storage: storage,
      );
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
            S.of(context).heroCardHint,
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
                      spec.titleFor(S.of(context)),
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
            S.of(context).heroPlayMode,
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
            S.of(context).heroPlayModeHint,
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
                      mode.titleFor(S.of(context)),
                      style: TextStyle(
                        color: playMode == mode ? onSurface : muted,
                        fontSize: 15,
                        fontWeight: playMode == mode
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      mode.captionFor(S.of(context)),
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

/// 大卡右侧抽样用的一首歌：歌本身 + 它在源歌单里的下标。
///
/// 下标必须留着——点某一首时要从这首歌开始播整张卡对应的队列，而不是
/// 只播它一个。
class HomeHeroSample {
  const HomeHeroSample({required this.song, required this.index});

  final MusicItem song;
  final int index;
}

/// 当前卡片里随机抽 3 首，给大卡右侧那列用。
///
/// 之前右侧是空的，只剩一枚声波水印；一张 380×168 的色块里只放左上角
/// 四行字，看着像没渲染完。抽三首真实的歌摆在右手，卡片就有了内容。
///
/// 按卡片 id 分槽并且 autoDispose：切到别的卡重新抽一批，但停在同一张
/// 卡上时不会因为父级 rebuild 又换一茬——刚看清歌名就变掉比空着更糟。
final homeHeroSamplesProvider = FutureProvider.autoDispose
    .family<List<HomeHeroSample>, HomeHeroCardId>((ref, id) async {
      final playlists = ref.watch(playlistsProvider);

      switch (id) {
        case HomeHeroCardId.favorites:
        case HomeHeroCardId.local:
        case HomeHeroCardId.recent:
          final playlistId = switch (id) {
            HomeHeroCardId.favorites => 'favorites',
            HomeHeroCardId.local => 'local',
            _ => 'recent',
          };
          final count =
              playlists
                  .where((playlist) => playlist.id == playlistId)
                  .firstOrNull
                  ?.songCount ??
              0;
          if (count == 0) return const <HomeHeroSample>[];
          final offsets = _randomOffsets(count, 3);
          final service = ref.read(playlistServiceProvider);
          // 一页一首：歌单可能有几千首，拉整页再挑会把首页拖慢。
          final pages = await Future.wait([
            for (final offset in offsets)
              service.getSongsPage(playlistId, offset: offset, limit: 1),
          ]);
          return <HomeHeroSample>[
            for (var i = 0; i < offsets.length; i++)
              if (pages[i].songs.isNotEmpty)
                HomeHeroSample(song: pages[i].songs.first, index: offsets[i]),
          ];
        case HomeHeroCardId.recommend:
          final songs =
              ref
                  .watch(recommendationProvider)
                  .valueOrNull
                  ?.map((item) => item.song)
                  .toList() ??
              const <MusicItem>[];
          return _sampleFrom(songs);
        case HomeHeroCardId.nas:
          final songs =
              ref.watch(subsonicLibrarySongsProvider).valueOrNull ??
              const <MusicItem>[];
          return _sampleFrom(songs);
      }
    });

/// 从 0..count-1 里挑不重复的若干个下标，升序返回。
List<int> _randomOffsets(int count, int wanted) {
  final random = Random();
  final picked = <int>{};
  final total = min(count, wanted);
  while (picked.length < total) {
    picked.add(random.nextInt(count));
  }
  return picked.toList()..sort();
}

/// 已经在内存里的歌（推荐 / NAS）：洗牌取 3 首，再按下标升序摆回来。
List<HomeHeroSample> _sampleFrom(List<MusicItem> songs) {
  if (songs.isEmpty) return const <HomeHeroSample>[];
  final indices = List<int>.generate(songs.length, (index) => index)
    ..shuffle(Random());
  final picked = indices.take(3).toList()..sort();
  return [
    for (final index in picked)
      HomeHeroSample(song: songs[index], index: index),
  ];
}

/// 首页那张大卡片：外观跟现在的收藏卡一致，内容随所选歌单卡切换。
class HomeHeroCard extends ConsumerWidget {
  const HomeHeroCard({super.key, this.height = defaultHeight});

  /// Portrait stage height. 218 made the card read as a full-bleed billboard;
  /// a large card that sits in the same rhythm as the shortcut tiles below it
  /// is easier to scan and leaves the page with a readable line length.
  static const double defaultHeight = 168;

  /// Fixed height, or null to fill the height its parent gives it. Landscape
  /// uses the fill mode so the card shares a row with the shortcut column
  /// instead of forcing a fixed 218 points of scroll.
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(homeHeroCardProvider);
    final spec = homeHeroCardOptions.firstWhere((item) => item.id == id);
    final playMode = ref.watch(homeHeroPlayModeProvider);
    final model = _resolve(context, ref, spec, playMode);
    const onAccent = Colors.white;
    final color = model.color;
    final title = spec.titleFor(S.of(context));

    final card = HoverFloat(
      child: Pressable(
        borderRadius: BorderRadius.circular(26),
        captureExpandRect: true,
        semanticLabel: title,
        onTap: model.onOpen,
        child: AnimatedSwitcher(
          duration: motionDuration(context, MotionDuration.container),
          switchInCurve: MotionCurve.iosSpring,
          switchOutCurve: MotionCurve.easeIn,
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: <Widget>[...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0.045, 0.02),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: _HeroStage(
            key: ValueKey(spec.id),
            spec: spec,
            model: model,
            title: title,
            color: color,
            onAccent: onAccent,
          ),
        ),
      ),
    );
    if (height == null) return card;
    return SizedBox(height: height, child: card);
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
          // 播放态不再显示提示行，subtitle 只服务空态。
          subtitle: S.of(context).noFavoritesYet,
          count: count,
          canPlay: count > 0,
          actionIcon: actionIcon,
          actionLabel: S
              .of(context)
              .playAction(
                playMode.titleFor(S.of(context)),
                S.of(context).favorites,
              ),
          onOpen: () => context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'favorites'},
          ),
          onPlay: () => _playFavorites(context, ref, playMode),
          // 点右侧某一首：还是这张卡的队列，只是从那一首开始。
          onPlayAt: (index) => _playPaged(
            context,
            ref,
            'favorites',
            count,
            playMode,
            startIndex: index,
          ),
        );
      case HomeHeroCardId.recommend:
        final recommendations =
            ref.watch(recommendationProvider).valueOrNull ?? const [];
        final count = recommendations.length;
        return _HeroModel(
          color: color,
          subtitle: S.of(context).recommendAfterFavorites,
          count: count,
          canPlay: count > 0,
          actionIcon: actionIcon,
          actionLabel: S
              .of(context)
              .playAction(
                playMode.titleFor(S.of(context)),
                S.of(context).forYou,
              ),
          onOpen: () => context.push('/recommend'),
          onPlay: () => _playRecommend(
            context,
            ref,
            recommendations.map((item) => item.song).toList(),
            playMode,
          ),
          onPlayAt: (index) => _playRecommend(
            context,
            ref,
            recommendations.map((item) => item.song).toList(),
            playMode,
            index: index,
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
          subtitle: S.of(context).chooseFolderToScan,
          count: count,
          canPlay: count > 0,
          actionIcon: actionIcon,
          actionLabel: S
              .of(context)
              .playAction(
                playMode.titleFor(S.of(context)),
                S.of(context).localMusic,
              ),
          onOpen: () => context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'local'},
          ),
          onPlay: () => _playPaged(context, ref, 'local', count, playMode),
          onPlayAt: (index) => _playPaged(
            context,
            ref,
            'local',
            count,
            playMode,
            startIndex: index,
          ),
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
        // subtitle 只服务空态：未配置 / 加载中给出说明，已连接但为空时
        // 什么都不写（播放态本来也不显示这行）。
        final subtitle = !connected
            ? S.of(context).nasHosts
            : subsonicConnected && songsAsync.isLoading
            ? S.of(context).loadingHost(config.hostLabel)
            : '';
        return _HeroModel(
          color: color,
          subtitle: subtitle,
          count: count,
          canPlay: subsonicConnected && count > 0,
          actionIcon: actionIcon,
          actionLabel: S
              .of(context)
              .playAction(
                playMode.titleFor(S.of(context)),
                S.of(context).nasLibrary,
              ),
          onOpen: () => context.push('/subsonic'),
          onPlay: () => _playNas(context, ref, songs, playMode),
          onPlayAt: (index) =>
              _playNas(context, ref, songs, playMode, index: index),
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
          subtitle: S.of(context).heroRecentEmpty,
          count: count,
          canPlay: count > 0,
          actionIcon: actionIcon,
          actionLabel: S
              .of(context)
              .playAction(
                playMode.titleFor(S.of(context)),
                S.of(context).recentPlays,
              ),
          onOpen: () => context.pushNamed(
            'playlistDetail',
            pathParameters: {'playlistId': 'recent'},
          ),
          onPlay: () => _playPaged(context, ref, 'recent', count, playMode),
          onPlayAt: (index) => _playPaged(
            context,
            ref,
            'recent',
            count,
            playMode,
            startIndex: index,
          ),
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
        showAppNotification(
          S.of(context).noFavoritesYet,
          type: AppNotificationType.info,
        );
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
        S.of(context).actionFailed(mode.titleFor(S.of(context)), error),
        type: AppNotificationType.error,
      );
    }
  }

  Future<void> _playPaged(
    BuildContext context,
    WidgetRef ref,
    String playlistId,
    int songCount,
    HomeHeroPlayMode mode, {

    /// 点右侧某一首时给进来：从这一首开始，不再按播放模式随机落点。
    int? startIndex,
  }) async {
    if (songCount <= 0) return;
    try {
      final playlistService = ref.read(playlistServiceProvider);
      final playerService = ref.read(playerServiceProvider);
      await _applyPlayMode(playerService, mode);
      await playerService.playPagedPlaylist(
        songCount: songCount,
        startIndex: startIndex ?? _startIndex(mode, songCount),
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
      showAppNotification(
        '${S.of(context).loadSongsFailed}: $error',
        type: AppNotificationType.error,
      );
    }
  }

  Future<void> _playRecommend(
    BuildContext context,
    WidgetRef ref,
    List<MusicItem> songs,
    HomeHeroPlayMode mode, {
    int? index,
  }) async {
    if (songs.isEmpty) return;
    try {
      final playerService = ref.read(playerServiceProvider);
      await _applyPlayMode(playerService, mode);
      final start = index ?? _startIndex(mode, songs.length);
      await playerService.playPlaylist(
        songs,
        index: start,
        manualPlayName: songs[start].name,
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppNotification(
        '${S.of(context).playFailed}: $error',
        type: AppNotificationType.error,
      );
    }
  }

  Future<void> _playNas(
    BuildContext context,
    WidgetRef ref,
    List<MusicItem> songs,
    HomeHeroPlayMode mode, {
    int? index,
  }) async {
    try {
      var queue = songs;
      if (queue.isEmpty) {
        queue = await ref.read(subsonicServiceProvider).getLibrarySongs();
      }
      if (queue.isEmpty) {
        showAppNotification(
          S.of(context).noSongsOnServer,
          type: AppNotificationType.info,
        );
        return;
      }
      final playerService = ref.read(playerServiceProvider);
      await _applyPlayMode(playerService, mode);
      final start = index ?? _startIndex(mode, queue.length);
      await playerService.playPlaylist(
        queue,
        index: start,
        manualPlayName: queue[start].name,
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppNotification(
        '${S.of(context).playFailed}: $error',
        type: AppNotificationType.error,
      );
    }
  }
}

class _HeroStage extends ConsumerWidget {
  const _HeroStage({
    super.key,
    required this.spec,
    required this.model,
    required this.title,
    required this.color,
    required this.onAccent,
  });

  final HomeHeroCardOption spec;
  final _HeroModel model;
  final String title;
  final Color color;
  final Color onAccent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = onAccent.withValues(alpha: 0.74);
    final iconColor = spec.id == HomeHeroCardId.favorites
        ? const Color(0xFFFF8A8A)
        : onAccent;
    final deep = Color.lerp(color, Colors.black, 0.58)!;
    // 抽样还没到（或这张卡是空的）就先不画——比画一个占位骨架安静。
    final samples =
        ref.watch(homeHeroSamplesProvider(spec.id)).valueOrNull ??
        const <HomeHeroSample>[];
    return OrigoChromeSurface(
      borderRadius: BorderRadius.circular(26),
      accent: color,
      emphasized: true,
      boxShadow: AppGlass.shadowFor(
        context,
        style: AppGlassStyle.regular,
        emphasized: true,
        accent: color,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Landscape stages are shorter than the portrait 218; drop the
          // eyebrow and shrink the controls so nothing clips.
          final compact = constraints.maxHeight < 150;
          // A stage stretched to a full landscape column needs a centred
          // composition; pinning everything to the top and bottom leaves a
          // big coloured void in the middle.
          final tall = constraints.maxHeight > 300;
          final pad = compact ? 16.0 : 20.0;
          final badge = compact ? 36.0 : (tall ? 46.0 : 42.0);
          // 播放键与左上角的徽标同尺寸：同一张卡上出现两个体量接近的圆角块
          // 会抢主体，等大之后它读成「卡片的第二枚图标」而不是独立按钮。
          final playSize = badge;
          // 右边这列只在真抽到歌时出现。宽度是量出来的：361 宽的竖屏卡，
          // 左边「徽标 42 + 间距 13 + 标题」在英文下要 180 左右
          // （"Recent plays" 20pt ≈ 125），再扣掉两边各 20 的内边距和 12 的
          // 列间距，只够给右手 130。
          //
          // 阈值原来写的是 300，横屏的 hero 只有 283 左右宽（竖屏是 336），
          // 于是横屏整列都画不出来。现在右列统一画（这是新布局的半壁江山），
          // 左列靠 FittedBox 缩标题兜底。
          final sampleWidth = (constraints.maxWidth * 0.36).clamp(118.0, 150.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Vertical two-tone wash: lit at the top, the card's own darker
              // shade at the bottom. A diagonal gradient plus a wide card
              // leaves most of the surface on one flat colour.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.46, 1],
                    colors: [
                      // The brand accent is a high-chroma green; at full
                      // strength across a large surface it reads as neon.
                      // Hold it back ~20% and let the top edge carry the
                      // highlight instead.
                      Color.lerp(color, Colors.white, 0.07)!,
                      Color.lerp(color, Colors.black, 0.28)!,
                      Color.lerp(color, Colors.black, 0.60)!,
                    ],
                  ),
                ),
              ),
              // Light falling in from the top-left corner, the way a printed
              // cover is lit. Without it the flat fill looks like paint.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: RadialGradient(
                    center: const Alignment(-0.85, -1.05),
                    radius: 1.25,
                    colors: [
                      onAccent.withValues(alpha: compact ? 0.10 : 0.16),
                      onAccent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              // Vignette. A cropped icon in the corner reads as a broken
              // sticker once the card is tall; a dark corner grounds the
              // surface and makes the white play button sit on something.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: RadialGradient(
                    center: const Alignment(0.95, 1.2),
                    radius: 1.15,
                    colors: [
                      Color.lerp(
                        color,
                        Colors.black,
                        0.55,
                      )!.withValues(alpha: compact ? 0.16 : 0.30),
                      Color.lerp(
                        color,
                        Colors.black,
                        0.55,
                      )!.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad + 2, pad, pad, pad - 2),
                child: Builder(
                  builder: (context) {
                    final badgeBox = Container(
                      width: badge,
                      height: badge,
                      decoration: BoxDecoration(
                        color: onAccent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(compact ? 13 : 15),
                        border: Border.all(
                          color: onAccent.withValues(alpha: 0.26),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        spec.icon,
                        color: iconColor,
                        size: compact ? 21 : (tall ? 25 : 24),
                      ),
                    );
                    // 右手那列吃掉一百三十点宽度后，英文标题（"Recently
                    // played"）在 20pt 下放不进剩下的位置了。scaleDown 让标题
                    // 按需缩半档，而不是变成 "Recently p…"；中文四字标题
                    // 本来就够宽，一点都不缩。
                    final titleText = FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: TextStyle(
                          color: onAccent,
                          fontSize: compact ? 17 : (tall ? 25 : 20),
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          letterSpacing: -0.3,
                        ),
                      ),
                    );
                    // 图标右侧就两行：标题，和作为副标题的歌曲数量。
                    // 「KOYZE / HOME」眉行和操作提示都不再画——前者是装饰，
                    // 后者与播放键的语义重复；数量是唯一有用的元信息。
                    final countText = model.count > 0
                        ? S.of(context).songCount(model.count)
                        : null;
                    final header = Row(
                      children: [
                        badgeBox,
                        SizedBox(width: compact ? 11 : 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              titleText,
                              if (countText != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  countText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: compact ? 11.5 : 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                    // 播放键钉在左下角，右侧整列让给那三首歌。
                    final playButton = Pressable(
                      scale: 0.92,
                      semanticLabel: model.actionLabel,
                      onTap: model.onPlay,
                      child: AnimatedContainer(
                        duration: motionDuration(
                          context,
                          MotionDuration.normal,
                        ),
                        curve: MotionCurve.iosSpring,
                        width: playSize,
                        height: playSize,
                        decoration: BoxDecoration(
                          color: onAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: deep.withValues(alpha: 0.34),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          model.actionIcon,
                          color: deep,
                          // 跟着圆钮缩：36 的钮配 17 的字重感才不挤。
                          size: playSize * 0.46,
                        ),
                      ),
                    );
                    if (!model.canPlay) {
                      // 空态整块居中：标题钉顶、说明钉底会在大片纯色中间留出
                      // 一块空洞，看着像没渲染完；收成一枚居中的海报更清楚。
                      // 同时不再画播放键——禁用的圆钮浮在色块里像坏掉的控件。
                      return Stack(
                        children: [
                          // 文字只占左侧三分之一，右边全空，卡片就读成「左边有
                          // 东西、右边没画完」。压一枚出血的声波水印把重量分到
                          // 右边，透明度足够低，不抢标题。
                          Positioned(
                            right: compact ? -6 : -14,
                            // 高卡把文案压到了底部，水印要挪到右上，否则和
                            // 标题撞在一起。
                            top: tall ? -18 : null,
                            bottom: tall ? null : (compact ? -8 : -16),
                            child: Icon(
                              Icons.graphic_eq_rounded,
                              size: compact
                                  ? 84
                                  : tall
                                  ? 148
                                  : 118,
                              color: onAccent.withValues(alpha: 0.13),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            // 空卡没有数量可以压底，跟着底部排会剩一大片纯色；
                            // 整块居中，卡片再高也像一张「空封面」而不是漏渲染。
                            //
                            // 但平板横屏的 hero 有 340pt 高，居中的文案
                            // 会浮在色块正中间，上下各空一百多 pt——那才是真的
                            // 漏渲染感。高卡改回海报式：标题压底，色彩留给上半。
                            mainAxisAlignment: tall
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.center,
                            children: [
                              badgeBox,
                              SizedBox(height: compact ? 10 : 14),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: titleText,
                              ),
                              if (model.subtitle.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    model.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: onAccent.withValues(alpha: 0.88),
                                      fontSize: compact ? 12 : 12.5,
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      );
                    }
                    // 统一的播放态布局：左列 = 顶部「图标 + 标题/数量」、
                    // 底部播放键；右列整高给那三首歌。竖屏、横屏、高卡都走
                    // 这一套——右侧列表被拉伸到全卡高度，窄卡的左列由
                    // FittedBox 把标题缩进来兜底，不再需要单独的堆叠分支。
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              header,
                              const Spacer(),
                              playButton,
                            ],
                          ),
                        ),
                        if (samples.isNotEmpty) ...[
                          const SizedBox(width: 14),
                          SizedBox(
                            width: sampleWidth,
                            child: _HeroSampleList(
                              samples: samples,
                              onPlayAt: model.onPlayAt,
                              onAccent: onAccent,
                              compact: compact,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 大卡右手那三首：像唱片背面的曲目表，一行一首，点一行就从那首开播。
///
/// 行高不写死，按父给的可用高度均分再夹在 18~24 之间——竖屏 168 的卡
/// 分到 22 左右，横屏那种被拉高的 hero 也不会散成三段。
class _HeroSampleList extends StatelessWidget {
  const _HeroSampleList({
    required this.samples,
    required this.onPlayAt,
    required this.onAccent,
    required this.compact,
  });

  final List<HomeHeroSample> samples;
  final ValueChanged<int> onPlayAt;
  final Color onAccent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // 三首之间要能点开。列高是固定的，gap 变大时行高会同比例变小，
        // 所以行距 = 28 + gap/3，只有 g/3 的收益——2/5 的时候两行字读成
        // 一整段，手指也常按到隔壁那首；推到 8/12 已经是行高能守住的极限
        // （再大行高就压到字以下，字会被裁）。
        final gap = compact ? 8.0 : 12.0;
        final available = box.hasBoundedHeight ? box.maxHeight : 84.0;
        final rowHeight =
            ((available - gap * (samples.length - 1)) / samples.length).clamp(
              compact ? 18.0 : 20.0,
              compact ? 24.0 : 26.0,
            );
        // 撑满父给的高度再居中：只有一两首时贴着顶边会和 kicker 挤在一起，
        // 读成它属于那行小字。
        return SizedBox(
          height: available,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < samples.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                // Flexible：卡再矮也只会把行压薄，不会撑出 overflow 的黄条。
                Flexible(child: _row(context, samples[i], rowHeight)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, HomeHeroSample sample, double height) {
    return Pressable(
      borderRadius: BorderRadius.circular(7),
      semanticLabel: sample.song.name,
      onTap: () => onPlayAt(sample.index),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Icon(
              Icons.play_arrow_rounded,
              size: compact ? 15 : 16,
              color: onAccent.withValues(alpha: 0.50),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                sample.song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onAccent.withValues(alpha: 0.86),
                  // 比标题（20）小一档：右列是曲目列表，压过标题就成了
                  // 第二主标题；再小回 11.5 又读不出歌名。
                  fontSize: compact ? 15.5 : 17.0,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    required this.onPlayAt,
  });

  final Color color;

  /// 空态说明（"还没有收藏" / "选择文件夹扫描"）。播放态不显示这行。
  final String subtitle;
  final int count;
  final bool canPlay;
  final IconData actionIcon;
  final String actionLabel;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  /// 右侧抽出来的某一首：从它在源歌单里的下标开始播。
  final ValueChanged<int> onPlayAt;
}
