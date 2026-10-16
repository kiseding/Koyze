import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../player/presentation/player_provider.dart';
import 'recommendation_provider.dart';
import '../../../core/widgets/adaptive_song_list.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/loading_widget.dart';

const Color kRecommendColor = Color(0xFFFF8F1F);

class RecommendationScreen extends ConsumerWidget {
  const RecommendationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendationsAsync = ref.watch(recommendationProvider);
    final playProvider = ref.read(playerServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          S.of(context).forYou,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.onScaffold(context),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: recommendationsAsync.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: AppLoadingIndicator()),
          error: (error, _) => _buildError(context, ref, error),
          data: (recommendations) => recommendations.isEmpty
              ? _buildEmpty(context)
              : AdaptiveSongList.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  landscapeItemExtent: 76,
                  itemCount: recommendations.length,
                  itemBuilder: (context, index) {
                    final rec = recommendations[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      leading: SizedBox(
                        width: 28,
                        child: Consumer(
                          builder: (context, ref, _) {
                            final isPlaying = ref.watch(
                              currentMusicProvider.select(
                                (current) =>
                                    current?.identityKey ==
                                    rec.song.identityKey,
                              ),
                            );
                            if (isPlaying) {
                              return Icon(
                                Icons.play_arrow,
                                size: 22,
                                color: AppColors.accentOf(context),
                              );
                            }
                            return Text(
                              '${index + 1}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: index < 3
                                    ? kRecommendColor
                                    : AppColors.mutedText(context),
                              ),
                            );
                          },
                        ),
                      ),
                      title: Text(
                        rec.song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.onScaffold(context),
                        ),
                      ),
                      subtitle: Text(
                        rec.reasons.isEmpty
                            ? rec.song.singer
                            : '${rec.song.singer} · ${rec.reasons.join('、')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedText(context),
                        ),
                      ),
                      trailing: FxIconButton(
                        tooltip: S.of(context).playNamed(rec.song.name),
                        icon: const Icon(
                          Icons.play_circle_outline,
                          size: 24,
                          color: kRecommendColor,
                        ),
                        onPressed: () => playProvider.playPlaylist(
                          recommendations.map((r) => r.song).toList(),
                          index: index,
                          manualPlayName: recommendations[index].song.name,
                        ),
                      ),
                      onTap: () => playProvider.playPlaylist(
                        recommendations.map((r) => r.song).toList(),
                        index: index,
                        manualPlayName: recommendations[index].song.name,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 56, color: kRecommendColor),
          const SizedBox(height: 12),
          Text(
            S.of(context).noRecommendations,
            style: TextStyle(color: AppColors.mutedText(context), fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            S.of(context).recommendationsNeedFavorites,
            style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, Object error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            '${S.of(context).loadFailed}: $error',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.secondaryText(context)),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => ref.read(recommendationProvider.notifier).retry(),
            child: Text(S.of(context).retry),
          ),
        ],
      ),
    );
  }
}
