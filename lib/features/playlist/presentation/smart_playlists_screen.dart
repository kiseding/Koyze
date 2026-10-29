import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../l10n/app_strings.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../../player/domain/music_item.dart';
import '../../player/presentation/player_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../stats/presentation/play_history_provider.dart';

/// 规则歌单依赖的本地歌曲，按「最近添加」排好序。
final _librarySongsProvider = FutureProvider<List<MusicItem>>((ref) async {
  final library = await ref.watch(localMusicLibraryProvider.future);
  await library.init();
  ref.watch(localMusicRevisionProvider);
  return library.songsByRecentlyAdded;
});

/// 智能歌单：不存歌单本体，每次打开按规则现算。
///
/// 存下来的规则歌单需要一套「什么时候重算」的机制（扫描后 / 听完一首后 /
/// 跨天后），每一处漏掉都会让用户看到过期的列表。现算没有这个问题，
/// 代价只是打开页面时读一次索引。
class SmartPlaylistsScreen extends ConsumerWidget {
  const SmartPlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final songsAsync = ref.watch(_librarySongsProvider);
    // 播放历史变化时要重算「最常播放 / 从未播放」。
    ref.watch(playHistoryRevisionProvider);
    final favorites =
        ref.watch(favoriteSongsProvider).valueOrNull ?? const <MusicItem>[];

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          leading: FxIconButton(
            tooltip: s.back,
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            s.smartPlaylists,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onScaffold(context),
            ),
          ),
        ),
        body: songsAsync.when(
          loading: () => const Center(child: AppLoadingIndicator()),
          error: (error, _) => Center(
            child: Text(
              '$error',
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
          data: (songs) {
            final store = ref.read(playHistoryStoreProvider);
            final playCounts = <String, int>{};
            for (final entry in store.entries) {
              playCounts.update(
                entry.songId,
                (value) => value + 1,
                ifAbsent: () => 1,
              );
            }
            final played =
                songs.where((song) => playCounts.containsKey(song.id)).toList()
                  ..sort(
                    (a, b) => (playCounts[b.id] ?? 0).compareTo(
                      playCounts[a.id] ?? 0,
                    ),
                  );
            final neverPlayed = songs
                .where((song) => !playCounts.containsKey(song.id))
                .toList();
            final rules = <_SmartRule>[
              _SmartRule(
                icon: Icons.fiber_new_rounded,
                title: s.smartRecentlyAdded,
                subtitle: s.smartRecentlyAddedHint,
                songs: songs,
              ),
              _SmartRule(
                icon: Icons.whatshot_rounded,
                title: s.smartMostPlayed,
                subtitle: s.smartMostPlayedHint,
                songs: played,
              ),
              _SmartRule(
                icon: Icons.music_off_rounded,
                title: s.smartNeverPlayed,
                subtitle: s.smartNeverPlayedHint,
                songs: neverPlayed,
              ),
              _SmartRule(
                icon: Icons.favorite_rounded,
                title: s.favorites,
                subtitle: s.smartFavoritesHint,
                songs: favorites,
              ),
            ];
            return ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
                16,
                32,
              ),
              children: [
                for (final rule in rules) ...[
                  _SmartRuleCard(rule: rule),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SmartRule {
  const _SmartRule({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.songs,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<MusicItem> songs;
}

class _SmartRuleCard extends ConsumerWidget {
  const _SmartRuleCard({required this.rule});

  final _SmartRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final enabled = rule.songs.isNotEmpty;
    return Material(
      color: AppColors.card(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled
            ? () => ref
                  .read(playerServiceProvider)
                  .setQueue(
                    rule.songs,
                    startIndex: 0,
                    manualPlayName: rule.songs.first.name,
                  )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accentOf(context).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  rule.icon,
                  color: AppColors.accentOf(context),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onScaffold(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      enabled
                          ? '${s.smartSongCount(rule.songs.length)} · ${rule.subtitle}'
                          : s.smartEmpty,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedText(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (enabled)
                Icon(
                  Icons.play_circle_fill_rounded,
                  color: AppColors.accentOf(context),
                  size: 30,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
