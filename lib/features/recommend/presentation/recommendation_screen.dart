import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../player/presentation/player_provider.dart';
import '../domain/recommendation_tuning.dart';
import 'recommendation_provider.dart';
import '../../../core/widgets/adaptive_song_list.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/loading_widget.dart';

const Color kRecommendColor = Color(0xFFFF8F1F);

class RecommendationScreen extends ConsumerStatefulWidget {
  const RecommendationScreen({super.key});

  @override
  ConsumerState<RecommendationScreen> createState() =>
      _RecommendationScreenState();
}

class _RecommendationScreenState extends ConsumerState<RecommendationScreen> {
  @override
  void initState() {
    super.initState();
    // 进来就问一句：歌单或收藏在上次见面之后变过的话，立刻重算，不再
    // 等 12 小时 TTL 或下一次冷启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(recommendationProvider.notifier).refreshIfStale(urgent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final recommendationsAsync = ref.watch(recommendationProvider);
    final tuning = ref.watch(recommendationTuningProvider);
    final playProvider = ref.read(playerServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        title: Text(
          S.of(context).forYou,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.onScaffold(context),
          ),
        ),
      ),
      // 列表滚到底 / 空态 / 键盘让位时，底下露出来的必须是页面底色。
      // 只靠 Scaffold.backgroundColor 时，body 里那些透明片段会落到上层
      // 的默认画布上，深色主题下就是一块刺眼的白。
      body: Material(
        color: AppColors.scaffold(context),
        // 底部安全区不在这里让位：列表要一直画到屏幕最底边。否则滚动视口
        // 会在 Home 指示条上方就结束，最后一行被齐刷刷砍断，下面还留一条
        // 空带——看起来就像凭空多出一块白。
        // 该留的间距改到列表自己的 bottom padding 里（见 _listPadding）。
        child: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              if (tuning.isNotEmpty) _tuningBar(context, ref, tuning),
              Expanded(
                child: recommendationsAsync.when(
                  skipLoadingOnReload: true,
                  skipLoadingOnRefresh: true,
                  loading: () => const SafeArea(
                    top: false,
                    child: Center(child: AppLoadingIndicator()),
                  ),
                  error: (error, _) => SafeArea(
                    top: false,
                    child: _buildError(context, ref, error),
                  ),
                  data: (recommendations) => RefreshIndicator(
                    color: kRecommendColor,
                    // 手动下拉永远绕过 TTL：用户都已经做出「刷新」这个动作了，
                    // 不该再被缓存挡一次。
                    onRefresh: () =>
                        ref.read(recommendationProvider.notifier).retry(),
                    child: recommendations.isEmpty
                        ? _buildEmptyScrollable(context)
                        : AdaptiveSongList.builder(
                            padding: _listPadding(context),
                            physics: const AlwaysScrollableScrollPhysics(),
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
                                  tooltip: S
                                      .of(context)
                                      .playNamed(rec.song.name),
                                  icon: const Icon(
                                    Icons.play_circle_outline,
                                    size: 24,
                                    color: kRecommendColor,
                                  ),
                                  onPressed: () => playProvider.playPlaylist(
                                    recommendations.map((r) => r.song).toList(),
                                    index: index,
                                    manualPlayName:
                                        recommendations[index].song.name,
                                  ),
                                ),
                                onTap: () => playProvider.playPlaylist(
                                  recommendations.map((r) => r.song).toList(),
                                  index: index,
                                  manualPlayName:
                                      recommendations[index].song.name,
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 被 AI 调整过时，在列表上方留一句话 + 一个重置入口。
  ///
  /// 不弹窗、不打断：用户可能只是想让助手帮着挑，改完之后最需要的是
  /// 「我知道这份推荐被改过，也能一键退回」。
  Widget _tuningBar(
    BuildContext context,
    WidgetRef ref,
    RecommendationTuning tuning,
  ) {
    final accent = AppColors.accentOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 13, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${S.of(context).recommendTunedByAi} · ${tuning.describe()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.mutedText(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(recommendationTuningProvider.notifier).clear();
              await ref.read(recommendationProvider.notifier).refresh();
              if (!context.mounted) return;
              showAppNotification(S.of(context).recommendTuningCleared);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: accent,
            ),
            child: Text(
              S.of(context).recommendTuningReset,
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 列表底部留白：24 的视觉呼吸 + 系统手势条高度。
  ///
  /// 页面已经画到屏幕底边，最后一行靠这段 padding 才不会被 Home 指示条
  /// 压住；同时滚到底时它还能正常露出来，不会被安全区「截断」。
  EdgeInsets _listPadding(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom);
  }

  /// 空态也要能下拉：没有候选往往正是最想重试的时候。
  Widget _buildEmptyScrollable(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = constraints.maxHeight > bottom
            ? constraints.maxHeight - bottom
            : 0.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: visible),
            child: _buildEmpty(context),
          ),
        );
      },
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
