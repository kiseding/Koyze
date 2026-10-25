import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';
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
import '../../../core/logging/app_log.dart';

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
    NotifierProvider<HomeHeroCardNotifier, HomeHeroCardId>(
      HomeHeroCardNotifier.new,
    );

typedef _EnumParser<T extends Enum> = T? Function(String? raw);

class _PersistentEnumNotifier<T extends Enum> extends BuildlessNotifier<T> {
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
      if (parsed != null && parsed != value) publish(parsed);
    } catch (error) {
      AppLog.instance.record(
        'home.hero',
        'loading hero card state failed: $error',
        level: AppLogLevel.info,
      );
    }
  }

  void select(T next) {
    if (value == next) return;
    publish(next);
    _persist();
  }

  Future<void> _persist() async {
    final generation = ++_generation;
    try {
      final storage = await _storage();
      if (generation != _generation) return;
      await storage.setString(_key, value.name);
    } catch (error) {
      AppLog.instance.record(
        'home.hero',
        'saving hero card state failed: $error',
        level: AppLogLevel.info,
      );
    }
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
    NotifierProvider<HomeHeroPlayModeNotifier, HomeHeroPlayMode>(
      HomeHeroPlayModeNotifier.new,
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

/// 当前卡片里随机抽 4 首，给大卡右侧那列用。
///
/// 之前右侧是空的，只剩一枚声波水印；一张 380×168 的色块里只放左上角
/// 四行字，看着像没渲染完。抽几首真实的歌摆在右手，卡片就有了内容。
/// 三首时每行要留 12 的缝隙才不粘在一起，四首改成等分 + 发丝线，行距
/// 反而更紧，信息却多一首。
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
          final offsets = _randomOffsets(count, homeHeroSampleMaxCount);
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

/// 大卡曲目最多抽几首。横屏那张卡排两列，6 首正好三行铺满；竖屏 168 的卡
/// 只排得下两行，用 [homeHeroPortraitSampleCount] 截掉后两首。这里统一按
/// 上限抽，竖屏只截列表——同一张卡在两种方向下是同一批歌，转屏不会整体
/// 换一批。
const homeHeroSampleMaxCount = 6;

/// 竖屏那张 168 高的卡显示几首：两列两行。
const homeHeroPortraitSampleCount = 4;

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

/// 已经在内存里的歌（推荐 / NAS）：洗牌取几首，再按下标升序摆回来。
List<HomeHeroSample> _sampleFrom(List<MusicItem> songs) {
  if (songs.isEmpty) return const <HomeHeroSample>[];
  final indices = List<int>.generate(songs.length, (index) => index)
    ..shuffle(Random());
  final picked = indices.take(homeHeroSampleMaxCount).toList()..sort();
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
    // 胶囊上写当前播放模式：「随机播放」读作「以随机方式播放」，比一枚
    // 只有循环箭头的圆钮好认。
    final playModeTitle = ref
        .watch(homeHeroPlayModeProvider)
        .titleFor(S.of(context));
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
          // 横屏那张卡有 240 高（竖屏只有 168），左列顶着一个标题、底压
          // 一个按钮，中间会空出一整块纯色。数量单独拎到中间那一行，
          // 高度用掉了，读起来也成了「标题 / 数量 / 操作」三段。
          final spread = constraints.maxHeight > 200;
          final pad = compact ? 16.0 : 20.0;
          final badge = compact ? 36.0 : (tall || spread ? 46.0 : 42.0);
          // 播放键从圆钮换成胶囊：原来那枚圆钮画的是播放模式图标
          // （顺序 / 随机 / 单曲），点下去却是「开始播放」，图标和动作对
          // 不上，只能靠猜。现在三角 + 模式名摆在一起，一句话说完。
          // 高度压在徽标之下（28/32 对 36/42），免得右下角那个块跟标题
          // 抢体量。
          final playChipHeight = compact ? 28.0 : 32.0;
          // 横屏放 6 首（两列三行铺满），竖屏只放得下 4 首。provider 按上限
          // 抽了 6 首，这里按当前高度截——两种方向下抽到的是同一批歌，只是
          // 竖屏少显示后两首，转屏时不会整体换一批。
          final visibleSamples = spread
              ? samples
              : samples.take(homeHeroPortraitSampleCount).toList();
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
              // 卡片自己的图形水印，无论有没有歌都在。
              //
              // 原来它只挂在空态分支上：一旦抽到歌就整块消失，同一张卡在
              // 「还没播」和「播过」之间换了一个底。现在提到背景层，尺寸
              // 按卡高的 0.85 算（照空态时 118/168 那个比例放一点）。
              // 曲目铺满下半张卡之后它整片压在歌名背后，所以出血从 0.20
              // 推到 0.26、有歌时压到 0.075：剩下的是一道底纹，不是一块要
              // 读的图形；到 0.12 就能看出白字被柱子切断。
              Positioned(
                right: -constraints.maxHeight * 0.26,
                bottom: -constraints.maxHeight * 0.26,
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: constraints.maxHeight * 0.85,
                  color: onAccent.withValues(
                    alpha: samples.isEmpty ? 0.13 : 0.075,
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
                        size: compact ? 21 : (tall || spread ? 25 : 24),
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
                          // 横屏那张卡有 240 高，20 的标题压不住整块面积，
                          // 提到 22；竖屏 168 保持 20。
                          fontSize: compact
                              ? 17
                              : (tall ? 25 : (spread ? 22 : 20)),
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
                    // 播放键钉在左下角，右侧整列让给那几首歌。宽度随文案
                    // 走（中文四字 / 英文 "Repeat one"），横屏左列只剩 111
                    // 的时候由 Flexible 收一点，不会把卡片撑破。
                    final playButton = Pressable(
                      scale: 0.94,
                      borderRadius: BorderRadius.circular(playChipHeight / 2),
                      semanticLabel: model.actionLabel,
                      onTap: model.onPlay,
                      child: AnimatedContainer(
                        duration: motionDuration(
                          context,
                          MotionDuration.normal,
                        ),
                        curve: MotionCurve.iosSpring,
                        height: playChipHeight,
                        padding: EdgeInsets.only(
                          left: compact ? 10 : 12,
                          right: compact ? 14 : 16,
                        ),
                        decoration: BoxDecoration(
                          color: onAccent,
                          borderRadius: BorderRadius.circular(
                            playChipHeight / 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: deep.withValues(alpha: 0.34),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow_rounded,
                              color: deep,
                              size: compact ? 15 : 17,
                            ),
                            SizedBox(width: compact ? 2 : 4),
                            Flexible(
                              child: Text(
                                playModeTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: TextStyle(
                                  color: deep,
                                  fontSize: compact ? 12 : 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (!model.canPlay) {
                      // 空态整块居中：标题钉顶、说明钉底会在大片纯色中间留出
                      // 一块空洞，看着像没渲染完；收成一枚居中的海报更清楚。
                      // 同时不再画播放键——禁用的圆钮浮在色块里像坏掉的控件。
                      // 空态只有一段说明，水印已经在背景层了，这里不再叠。
                      return Column(
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
                      );
                    }
                    // 播放态：顶部一行（徽标 + 标题/数量 + 播放键），下面
                    // 整片交给曲目。
                    //
                    // 旧结构是左右分栏——左列顶着标题、底压按钮、中间 Spacer。
                    // 卡高 168 时那根 Spacer 会空出 56：它不是留白，是算剩
                    // 的（标题 44 + 按钮 32，余下的全归它）。往 56 里塞任何
                    // 部件都只能是「一行小字」，塞得越多越像没画完。改成
                    // 上下两段之后，需要那块空间的格子被曲目占掉了。
                    //
                    // 两种方向都排两列：竖屏 294 宽每格 140，横屏 241 宽
                    // 每格 113。横屏格子窄，序号间距和字号各收一档（dense
                    // 由卡宽判定）；6 首正好两列三行，没有空格子。
                    final dense = constraints.maxWidth < 300;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: header),
                            SizedBox(width: compact ? 8 : 10),
                            playButton,
                          ],
                        ),
                        if (visibleSamples.isNotEmpty) ...[
                          SizedBox(height: compact ? 8 : 12),
                          Expanded(
                            child: _HeroSampleGrid(
                              samples: visibleSamples,
                              onPlayAt: model.onPlayAt,
                              onAccent: onAccent,
                              compact: compact,
                              dense: dense,
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

/// 大卡下面那片曲目：两列铺满，点哪首就从哪首开播。
///
/// 行高靠 Flexible 均分，不写死——竖屏四首两行各 39，横屏六首三行各 50；
/// 卡被拉高到 340 时也只把行撑开，不会散成八行。
class _HeroSampleGrid extends StatelessWidget {
  const _HeroSampleGrid({
    required this.samples,
    required this.onPlayAt,
    required this.onAccent,
    required this.compact,
    required this.dense,
  });

  final List<HomeHeroSample> samples;
  final ValueChanged<int> onPlayAt;
  final Color onAccent;
  final bool compact;

  /// 卡窄到 300 以下（横屏那张 283 的 hero）：每格只有 113 宽，序号间距
  /// 和歌名字号各收一档，否则稍长的歌名一律带省略号。
  final bool dense;

  static const _columns = 2;

  @override
  Widget build(BuildContext context) {
    final rows = (samples.length / _columns).ceil();
    return LayoutBuilder(
      builder: (context, box) {
        final available = box.hasBoundedHeight ? box.maxHeight : 120.0;
        // 行高均分，但有上限：只有一两首时均分会把一行撑到 78 高，字浮在
        // 一个空盒子的正中间，比排得紧还难看。单行封在 56（一行字 + 上下
        // 留白），多行给到 64——再多就会在卡片底部又留出一块空地，正是
        // 这次要消掉的东西。
        //
        // 均分时要先把发丝线占的位置（0.5 × 行数-1）扣掉：不扣的话两行
        // 竖屏正好超出 0.5，调试包里会画一条黄黑警示条。
        final cap = rows == 1 ? 56.0 : 64.0;
        final dividers = 0.5 * (rows - 1);
        final rowHeight = ((available - dividers) / rows).clamp(0.0, cap);
        return Column(
          // 顶对齐而不是居中：只有一两首时（新装机的最近播放就是这样）
          // 居中的单行会浮在卡片正中间，读成一张空卡加一行字；顶对齐时它
          // 紧跟在标题下面，剩下的空地正好交给右下角那枚水印。
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0)
                // 发丝线贯通整行，不是每格各画一条：两列时也要一整条横线，
                // 否则读成四张互不相干的小卡。
                Container(height: 0.5, color: onAccent.withValues(alpha: 0.12)),
              SizedBox(height: rowHeight, child: _rowOf(row)),
            ],
          ],
        );
      },
    );
  }

  Widget _rowOf(int row) {
    final first = row * _columns;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _cell(first)),
        const SizedBox(width: 14),
        // 奇数首时右格留空，不然后一首会被拉成两倍宽。
        Expanded(child: _cell(first + 1)),
      ],
    );
  }

  Widget _cell(int index) {
    if (index >= samples.length) return const SizedBox.shrink();
    final sample = samples[index];
    final ordinal = index + 1;
    return Pressable(
      borderRadius: BorderRadius.circular(7),
      semanticLabel: sample.song.name,
      onTap: () => onPlayAt(sample.index),
      // 整格都是热区：格子铺满之后，手指按在哪都不会落到两首之间。
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            // 序号把这几行读成一张曲目表；没有它，只是几段孤立的歌名。
            Text(
              ordinal.toString().padLeft(2, '0'),
              style: TextStyle(
                color: onAccent.withValues(alpha: 0.40),
                fontSize: compact ? 11 : 11.5,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
            SizedBox(width: compact || dense ? 7 : 9),
            Expanded(
              child: Text(
                sample.song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onAccent.withValues(alpha: 0.88),
                  // 两列每格只有 113~140，15 号字放不下九字歌名：竖屏
                  // 留 14，横屏再收半档到 13.5。
                  fontSize: compact ? 13 : (dense ? 13.5 : 14.0),
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
  final String actionLabel;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  /// 右侧抽出来的某一首：从它在源歌单里的下标开始播。
  final ValueChanged<int> onPlayAt;
}
