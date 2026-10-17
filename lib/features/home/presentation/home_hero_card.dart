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

  Color colorOf(BuildContext context) => color ?? AppColors.accentOf(context);

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

/// 首页那张大卡片：外观跟现在的收藏卡一致，内容随所选歌单卡切换。
class HomeHeroCard extends ConsumerWidget {
  const HomeHeroCard({super.key, this.height = defaultHeight});

  /// Portrait stage height.
  static const double defaultHeight = 218;

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
          subtitle: count == 0
              ? S.of(context).noFavoritesYet
              : S
                    .of(context)
                    .heroFavoritesHint(playMode.titleFor(S.of(context))),
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
        );
      case HomeHeroCardId.recommend:
        final recommendations =
            ref.watch(recommendationProvider).valueOrNull ?? const [];
        final count = recommendations.length;
        return _HeroModel(
          color: color,
          subtitle: count > 0
              ? S.of(context).recommendedSongs(count)
              : S.of(context).recommendAfterFavorites,
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
          subtitle: count == 0
              ? S.of(context).chooseFolderToScan
              : S.of(context).songCount(count),
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
            ? S.of(context).nasHosts
            : subsonicConnected && songsAsync.isLoading
            ? S.of(context).loadingHost(config.hostLabel)
            : 'NAS';
        return _HeroModel(
          color: color,
          subtitle: subtitle,
          count: count,
          showCountInTitle: false,
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
          subtitle: S.of(context).songCount(count),
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
    HomeHeroPlayMode mode,
  ) async {
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
      final index = _startIndex(mode, queue.length);
      await playerService.playPlaylist(
        queue,
        index: index,
        manualPlayName: queue[index].name,
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

class _HeroStage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final muted = onAccent.withValues(alpha: 0.74);
    final iconColor = spec.id == HomeHeroCardId.favorites
        ? const Color(0xFFFF8A8A)
        : onAccent;
    final deep = Color.lerp(color, Colors.black, 0.58)!;
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
          final compact = constraints.maxHeight < 176;
          // A stage stretched to a full landscape column needs a centred
          // composition; pinning everything to the top and bottom leaves a
          // big coloured void in the middle.
          final tall = constraints.maxHeight > 300;
          final pad = compact ? 16.0 : 20.0;
          final badge = compact ? 38.0 : (tall ? 48.0 : 46.0);
          final playSize = compact ? 44.0 : (tall ? 52.0 : 50.0);
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
                      Color.lerp(color, Colors.white, 0.14)!,
                      Color.lerp(color, Colors.black, 0.20)!,
                      Color.lerp(color, Colors.black, 0.52)!,
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
                    final eyebrow = Text(
                      'KOYZE / HOME',
                      style: TextStyle(
                        color: muted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    );
                    final titleText = Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onAccent,
                        fontSize: compact ? 18 : (tall ? 26 : 21),
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        letterSpacing: -0.3,
                      ),
                    );
                    final titleRow = Row(
                      children: [
                        badgeBox,
                        SizedBox(width: compact ? 11 : 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!compact) ...[
                                eyebrow,
                                const SizedBox(height: 5),
                              ],
                              titleText,
                            ],
                          ),
                        ),
                      ],
                    );
                    final metaRow = Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (model.showCountInTitle && model.count > 0)
                                Text(
                                  S.of(context).songCount(model.count),
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (model.showCountInTitle && model.count > 0)
                                const SizedBox(height: 3),
                              Text(
                                model.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: onAccent.withValues(alpha: 0.92),
                                  fontSize: compact ? 12 : 12.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Pressable(
                          scale: 0.92,
                          semanticLabel: model.actionLabel,
                          onTap: model.canPlay ? model.onPlay : null,
                          child: AnimatedContainer(
                            duration: motionDuration(
                              context,
                              MotionDuration.normal,
                            ),
                            curve: MotionCurve.iosSpring,
                            width: playSize,
                            height: playSize,
                            decoration: BoxDecoration(
                              color: model.canPlay
                                  ? onAccent
                                  : onAccent.withValues(alpha: 0.26),
                              shape: BoxShape.circle,
                              boxShadow: [
                                if (model.canPlay)
                                  BoxShadow(
                                    color: deep.withValues(alpha: 0.34),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                              ],
                            ),
                            child: Icon(
                              model.actionIcon,
                              color: model.canPlay ? deep : muted,
                              size: compact ? 21 : 23,
                            ),
                          ),
                        ),
                      ],
                    );
                    if (tall) {
                      // Poster: a tall stage keeps the top to the gradient and
                      // stacks badge, eyebrow and headline at the bottom the
                      // way a cover carries its caption.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          badgeBox,
                          const SizedBox(height: 14),
                          if (!compact) ...[eyebrow, const SizedBox(height: 6)],
                          titleText,
                          const SizedBox(height: 16),
                          metaRow,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: titleRow,
                          ),
                        ),
                        metaRow,
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
