import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/adaptive_song_list.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../local_music/domain/local_music_scraper.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../../local_music/presentation/scrape_provider.dart';
import '../../nas/domain/nas_kind.dart';
import '../../nas/domain/nas_library_groups.dart';
import '../../nas/domain/self_hosted_kind.dart';
import '../../nas/presentation/nas_provider.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import 'subsonic_provider.dart';
import '../../../core/widgets/loading_widget.dart';

class SubsonicLibraryScreen extends ConsumerStatefulWidget {
  const SubsonicLibraryScreen({super.key});

  @override
  ConsumerState<SubsonicLibraryScreen> createState() =>
      _SubsonicLibraryScreenState();
}

class _SubsonicLibraryScreenState extends ConsumerState<SubsonicLibraryScreen> {
  bool _scraping = false;
  bool _refreshing = false;
  int _scrapeDone = 0;
  int _scrapeTotal = 0;

  void _invalidateSongs(SelfHostedKind kind) {
    final nasKind = kind.nasKind;
    if (nasKind == null) {
      ref.invalidate(subsonicLibrarySongsProvider);
    } else {
      ref.invalidate(nasLibrarySongsProvider(nasKind));
    }
  }

  /// 刷新按钮：绕过缓存整库重扫。以前这里只是 invalidate，重新进页面还是走
  /// 缓存，用户会以为「刷新没反应」。
  Future<void> _refreshSongs(SelfHostedKind kind) async {
    final nasKind = kind.nasKind;
    if (nasKind == null) {
      ref.invalidate(subsonicLibrarySongsProvider);
      return;
    }
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await refreshNasLibrary(ref, nasKind);
    } catch (error) {
      if (mounted) {
        showAppNotification(
          '${S.of(context).loadSongsFailed}: $error',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = ref.watch(selfHostedKindProvider);
    final nasKind = kind.nasKind;
    final subsonicConnected = ref.watch(subsonicConnectedProvider);
    final nasConnected = nasKind == null
        ? false
        : ref.watch(nasConnectedProvider(nasKind));
    final connected = nasKind == null ? subsonicConnected : nasConnected;
    final configHost = nasKind == null
        ? ref.watch(subsonicConfigProvider).hostLabel
        : ref.watch(nasConfigProvider(nasKind)).hostLabel;
    final songsAsync = nasKind == null
        ? ref.watch(subsonicLibrarySongsProvider)
        : ref.watch(nasLibrarySongsProvider(nasKind));
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    final accent = AppColors.accentOf(context);
    final showFolders = nasKind == NasKind.webdav;
    final tabLabels = <String>[
      S.of(context).songs,
      S.of(context).albums,
      S.of(context).artists,
      if (showFolders) S.of(context).folders,
    ];
    final tabCount = tabLabels.length;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          leading: FxIconButton(
            tooltip: S.of(context).back,
            icon: Icon(Icons.arrow_back, color: on),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            S.of(context).nasLibrary,
            style: TextStyle(
              color: on,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            FxIconButton(
              tooltip: S.of(context).connectionSettings,
              icon: Icon(Icons.settings_outlined, color: on),
              onPressed: () => context.push('/subsonic-settings', extra: kind),
            ),
            if (connected)
              songsAsync.maybeWhen(
                data: (songs) => songs.isEmpty
                    ? const SizedBox.shrink()
                    : FxIconButton(
                        tooltip: S.of(context).playAll,
                        icon: Icon(
                          Icons.play_circle_fill,
                          color: accent,
                          size: 28,
                        ),
                        onPressed: () => _play(songs, 0),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            if (connected)
              songsAsync.maybeWhen(
                data: (songs) => songs.isEmpty
                    ? const SizedBox.shrink()
                    : FxIconButton(
                        tooltip: _scraping
                            ? S.of(context).scraping
                            : S.of(context).scrapeArtworkLyrics,
                        icon: Icon(
                          Icons.auto_fix_high_outlined,
                          color: _scraping ? accent : on,
                        ),
                        onPressed: _scraping
                            ? null
                            : () => _scrape(songs, kind),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            if (connected)
              FxIconButton(
                tooltip: S.of(context).refresh,
                icon: _refreshing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: AppLoadingIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(Icons.refresh, color: on),
                onPressed: _scraping || _refreshing
                    ? null
                    : () => _refreshSongs(kind),
              ),
          ],
          bottom: connected && tabCount > 1
              ? TabBar(
                  isScrollable: false,
                  labelColor: on,
                  unselectedLabelColor: muted,
                  indicatorColor: accent,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: [for (final label in tabLabels) Tab(text: label)],
                )
              : null,
        ),
        extendBodyBehindAppBar: true,
        body: KoyzeAppBarBody(
          child: Column(
            children: [
              if (_scraping)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: GlassSurface(
                    style: AppGlassStyle.regular,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.fromBorderSide(
                      AppGlass.hairline(context, emphasized: false),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LinearProgressIndicator(
                          value: _scrapeTotal == 0
                              ? null
                              : _scrapeDone / _scrapeTotal,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          S
                              .of(context)
                              .scrapingProgress(_scrapeDone, _scrapeTotal),
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: !connected
                    ? _empty(
                        context,
                        icon: Icons.cloud_off_outlined,
                        title: S.of(context).notConnected(kind.title),
                        subtitle: kind.intro,
                        actionLabel: S.of(context).goConnect,
                        onAction: () =>
                            context.push('/subsonic-settings', extra: kind),
                      )
                    : songsAsync.when(
                        loading: () =>
                            const Center(child: AppLoadingIndicator()),
                        error: (error, _) => _empty(
                          context,
                          icon: Icons.error_outline,
                          title: S.of(context).loadSongsFailed,
                          subtitle: '$error',
                          actionLabel: S.of(context).retry,
                          onAction: () => _invalidateSongs(kind),
                        ),
                        data: (songs) {
                          if (songs.isEmpty) {
                            return _empty(
                              context,
                              icon: Icons.library_music_outlined,
                              title: S.of(context).noSongsOnServer,
                              subtitle: S.of(context).connectedHost(configHost),
                              actionLabel: S.of(context).refresh,
                              onAction: () => _refreshSongs(kind),
                            );
                          }
                          if (tabCount == 1) return _songList(songs);
                          return TabBarView(
                            children: [
                              _songList(songs),
                              _collectionList(
                                context,
                                groupNasSongs(
                                  songs,
                                  NasGrouping.album,
                                  unknownAlbum: S.of(context).unknownAlbum,
                                  unknownArtist: S.of(context).unknownArtist,
                                ),
                                icon: Icons.album_outlined,
                              ),
                              _collectionList(
                                context,
                                groupNasSongs(
                                  songs,
                                  NasGrouping.artist,
                                  unknownAlbum: S.of(context).unknownAlbum,
                                  unknownArtist: S.of(context).unknownArtist,
                                ),
                                icon: Icons.person_outline,
                              ),
                              if (showFolders)
                                _collectionList(
                                  context,
                                  groupNasSongs(
                                    songs,
                                    NasGrouping.folder,
                                    unknownAlbum: S.of(context).unknownAlbum,
                                    unknownArtist: S.of(context).unknownArtist,
                                  ),
                                  icon: Icons.folder_outlined,
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _songList(List<MusicItem> songs) {
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    return AdaptiveSongList.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
      landscapeItemExtent: 82,
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          onTap: () => _play(songs, index),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: song.artwork == null || song.artwork!.isEmpty
                  ? Icon(Icons.music_note, color: muted)
                  : ArtworkImage(
                      song.artwork!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.music_note, color: muted),
                    ),
            ),
          ),
          title: Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: on, fontSize: 14),
          ),
          subtitle: Text(
            [
              if (song.singer.trim().isNotEmpty) song.singer,
              if (song.album.trim().isNotEmpty) song.album,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: 12),
          ),
          trailing: FavoriteButton(song: song),
        );
      },
    );
  }

  Widget _collectionList(
    BuildContext context,
    List<NasCollection> collections, {
    required IconData icon,
  }) {
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
      itemCount: collections.length,
      itemBuilder: (context, index) {
        final collection = collections[index];
        return ListTile(
          onTap: () => context.push('/subsonic/collection', extra: collection),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: collection.artwork == null
                  ? ColoredBox(
                      color: AppGlass.fill(
                        context,
                        style: AppGlassStyle.regular,
                      ),
                      child: Icon(icon, color: muted, size: 22),
                    )
                  : ArtworkImage(
                      collection.artwork!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Icon(icon, color: muted, size: 22),
                    ),
            ),
          ),
          title: Text(
            collection.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: on, fontSize: 14),
          ),
          subtitle: Text(
            [
              if (collection.subtitle.trim().isNotEmpty) collection.subtitle,
              S.of(context).songCountValue(collection.songs.length),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
        );
      },
    );
  }

  Future<void> _scrape(List<MusicItem> songs, SelfHostedKind kind) async {
    if (_scraping || songs.isEmpty) return;
    setState(() {
      _scraping = true;
      _scrapeDone = 0;
      _scrapeTotal = songs.length;
    });
    try {
      final scraper = ref.read(localMusicScraperProvider);
      final store = await ref.read(musicScrapeStoreProvider.future);
      final matched = await scrapeMusicItems(
        scraper: scraper,
        store: store,
        songs: songs,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _scrapeDone = done;
            _scrapeTotal = total;
          });
        },
      );
      if (!mounted) return;
      ref.read(scrapeRevisionProvider.notifier).state++;
      _invalidateSongs(kind);
      showAppNotification(
        matched == 0
            ? S.of(context).noOnlineMatch
            : S.of(context).matchedSongs(matched, songs.length),
      );
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        S.of(context).scrapeFailed(error),
        type: AppNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _scraping = false);
    }
  }

  Future<void> _play(List<MusicItem> songs, int index) async {
    if (songs.isEmpty) return;
    try {
      await ref
          .read(playerServiceProvider)
          .playPlaylist(songs, index: index, manualPlayName: songs[index].name);
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        '${S.of(context).playFailed}: $error',
        type: AppNotificationType.error,
      );
    }
  }

  Widget _empty(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final muted = AppColors.mutedText(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onScaffold(context),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
