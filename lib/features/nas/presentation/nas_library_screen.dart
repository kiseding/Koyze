import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../local_music/domain/local_music_scraper.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../../local_music/presentation/scrape_provider.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../domain/nas_kind.dart';
import 'nas_provider.dart';

class NasLibraryScreen extends ConsumerStatefulWidget {
  const NasLibraryScreen({super.key, required this.kind});

  final NasKind kind;

  @override
  ConsumerState<NasLibraryScreen> createState() => _NasLibraryScreenState();
}

class _NasLibraryScreenState extends ConsumerState<NasLibraryScreen> {
  bool _scraping = false;
  int _scrapeDone = 0;
  int _scrapeTotal = 0;

  NasKind get kind => widget.kind;

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(nasConnectedProvider(kind));
    final config = ref.watch(nasConfigProvider(kind));
    final songsAsync = ref.watch(nasLibrarySongsProvider(kind));
    final on = AppColors.onScaffold(context);
    final accent = AppColors.accentOf(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: FxIconButton(
          tooltip: S.of(context).back,
          icon: Icon(Icons.arrow_back, color: on),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          kind.libraryTitle,
          style: TextStyle(color: on, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          FxIconButton(
            tooltip: S.of(context).connectionSettings,
            icon: Icon(Icons.settings_outlined, color: on),
            onPressed: () => context.push(kind.settingsRoute),
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
                      tooltip: _scraping ? S.of(context).scraping : S.of(context).scrapeArtworkLyrics,
                      icon: Icon(
                        Icons.auto_fix_high_outlined,
                        color: _scraping ? accent : on,
                      ),
                      onPressed: _scraping ? null : () => _scrape(songs),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          if (connected)
            FxIconButton(
              tooltip: S.of(context).refresh,
              icon: Icon(Icons.refresh, color: on),
              onPressed: _scraping
                  ? null
                  : () => ref.invalidate(nasLibrarySongsProvider(kind)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_scraping)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: _scrapeTotal == 0 ? null : _scrapeDone / _scrapeTotal,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.of(context).scrapingProgress(_scrapeDone, _scrapeTotal),
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: !connected
                ? _empty(
                    context,
                    icon: Icons.cloud_off_outlined,
                    title: S.of(context).notConnected(kind.title),
                    subtitle: kind.settingsSubtitle,
                    actionLabel: S.of(context).goConnect,
                    onAction: () => context.push(kind.settingsRoute),
                  )
                : songsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _empty(
                      context,
                      icon: Icons.error_outline,
                      title: S.of(context).loadSongsFailed,
                      subtitle: '$error',
                      actionLabel: S.of(context).retry,
                      onAction: () =>
                          ref.invalidate(nasLibrarySongsProvider(kind)),
                    ),
                    data: (songs) {
                      if (songs.isEmpty) {
                        return _empty(
                          context,
                          icon: Icons.library_music_outlined,
                          title: S.of(context).noSongsOnServer,
                          subtitle: S.of(context).connectedHost(config.hostLabel),
                          actionLabel: S.of(context).refresh,
                          onAction: () =>
                              ref.invalidate(nasLibrarySongsProvider(kind)),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
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
                                child: song.artwork == null ||
                                        song.artwork!.isEmpty
                                    ? Icon(
                                        Icons.music_note,
                                        color: AppColors.mutedText(context),
                                      )
                                    : ArtworkImage(
                                        song.artwork!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.music_note,
                                          color: AppColors.mutedText(context),
                                        ),
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
                              style: TextStyle(
                                color: AppColors.mutedText(context),
                                fontSize: 12,
                              ),
                            ),
                            trailing: FavoriteButton(song: song),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _scrape(List<MusicItem> songs) async {
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
      ref.invalidate(nasLibrarySongsProvider(kind));
      showAppNotification(
        matched == 0
            ? S.of(context).noOnlineMatch
            : S.of(context).matchedSongs(matched, songs.length),
      );
    } catch (error) {
      if (!mounted) return;
      showAppNotification(S.of(context).scrapeFailed(error), type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _scraping = false);
    }
  }

  Future<void> _play(List<MusicItem> songs, int index) async {
    if (songs.isEmpty) return;
    try {
      await ref.read(playerServiceProvider).playPlaylist(
            songs,
            index: index,
            manualPlayName: songs[index].name,
          );
    } catch (error) {
      showAppNotification('${S.of(context).playFailed}: $error', type: AppNotificationType.error);
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
