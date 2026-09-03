import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koyze/core/music_source/platform/music_platform.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/features/leaderboard/presentation/leaderboard_provider.dart';
import 'package:koyze/features/leaderboard/presentation/leaderboard_screen.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';

/// 榜单设置：勾选显示哪些平台与榜单。
/// 平台未勾选时，其所属榜单不可勾选（自动隐藏并禁用）。
class LeaderboardSettingsScreen extends ConsumerWidget {
  const LeaderboardSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(leaderboardCategoriesProvider);
    final layout = ref.watch(leaderboardLayoutProvider);

    final hiddenByKey = <String, bool>{
      for (final item in layout) item.key: item.hidden,
    };

    // 平台分组：平台头 + 其下榜单
    final grouped = <String, List<LeaderboardCategory>>{};
    for (final category
        in categoriesAsync.valueOrNull ?? const <LeaderboardCategory>[]) {
      final key = category.platform ?? 'other';
      grouped.putIfAbsent(key, () => []).add(category);
    }
    // 布局顺序优先，其余平台追加。
    final platformKeys = <String>[
      ...layout
          .where((item) => item.isPlatform)
          .map((item) => item.platformId!)
          .where(grouped.containsKey),
      ...grouped.keys.where(
        (key) =>
            !layout.any((item) => item.isPlatform && item.platformId == key),
      ),
    ];

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 列表可滚动到栏内部（栏高度不变），顶栏磨砂才可见。
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          // 顶栏整栏磨砂玻璃，无底部渐变透明。
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          leading: FxIconButton(
            tooltip: '返回',
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            '榜单设置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onScaffold(context),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                ref.read(leaderboardLayoutProvider.notifier).restoreAll();
              },
              icon: const Icon(Icons.visibility_rounded, size: 17),
              label: const Text('全部显示'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentOf(context),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        body: categoriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              '加载失败: $error',
              style: TextStyle(color: AppColors.mutedText(context)),
            ),
          ),
          data: (categories) {
            if (categories.isEmpty) {
              return Center(
                child: Text(
                  '暂无排行榜数据',
                  style: TextStyle(color: AppColors.mutedText(context)),
                ),
              );
            }
            final notifier = ref.read(leaderboardLayoutProvider.notifier);
            return ListView(
              padding: EdgeInsets.fromLTRB(
                12,
                MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
                12,
                24,
              ),
              children: [
                for (final platform in platformKeys) ...[
                  _buildPlatformSection(
                    context,
                    ref,
                    platform,
                    grouped[platform]!,
                    hiddenByKey,
                    notifier,
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlatformSection(
    BuildContext context,
    WidgetRef ref,
    String platform,
    List<LeaderboardCategory> categories,
    Map<String, bool> hiddenByKey,
    LeaderboardLayoutNotifier notifier,
  ) {
    final name = kLeaderboardPlatformNames[platform] ?? '其他';
    final color = _platformColor(context, platform);
    final platformKey = 'platform:$platform';
    final platformHidden = hiddenByKey[platformKey] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 平台勾选开关
        Container(
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder(context)),
          ),
          child: ListTile(
            onTap: () {
              if (platformHidden) {
                notifier.restoreItem(platformKey);
              } else {
                notifier.hidePlatform(platform);
              }
            },
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_platformIcon(platform), color: color, size: 20),
            ),
            title: Row(
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onScaffold(context),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${categories.length} 个榜单${platform == 'tx' ? ' · 默认优先' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.mutedText(context),
              ),
            ),
            trailing: FxSwitch(
              value: !platformHidden,
              activeColor: color,
              onChanged: (enabled) {
                if (enabled) {
                  notifier.restoreItem(platformKey);
                } else {
                  notifier.hidePlatform(platform);
                }
              },
            ),
          ),
        ),
        // 该平台的榜单（平台未勾选时禁用且不可单独勾选）
        if (platformHidden)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 0, 0),
            child: Text(
              '已隐藏，勾选「$name」后显示',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.mutedText(context),
              ),
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: AppColors.fill(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder(context)),
            ),
            child: Column(
              children: [
                for (var index = 0; index < categories.length; index++) ...[
                  _CategoryVisibilityTile(
                    category: categories[index],
                    color: color,
                    visible:
                        !(hiddenByKey['category:${categories[index].id}'] ??
                            false),
                    onChanged: (visible) {
                      if (visible) {
                        notifier.restoreItem(
                          'category:${categories[index].id}',
                        );
                      } else {
                        notifier.hideCategory(categories[index].id);
                      }
                    },
                  ),
                  if (index < categories.length - 1)
                    Divider(height: 1, color: AppColors.cardBorder(context)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Color _platformColor(BuildContext context, String platform) {
    switch (platform) {
      case 'kw':
        return const Color(0xFF6B3FA0);
      case 'tx':
        return const Color(0xFF2355C0);
      case 'wy':
        return const Color(0xFF9B3060);
      default:
        return AppColors.accentOf(context);
    }
  }

  IconData _platformIcon(String platform) {
    switch (platform) {
      case 'tx':
        return Icons.music_note_rounded;
      case 'kw':
        return Icons.graphic_eq_rounded;
      case 'wy':
        return Icons.album_rounded;
      default:
        return Icons.library_music_rounded;
    }
  }
}

class _CategoryVisibilityTile extends StatelessWidget {
  const _CategoryVisibilityTile({
    required this.category,
    required this.color,
    required this.visible,
    required this.onChanged,
  });

  final LeaderboardCategory category;
  final Color color;
  final bool visible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: () => onChanged(!visible),
      leading: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: visible ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: visible ? color : AppColors.mutedText(context),
          ),
        ),
        child: visible
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 17)
            : null,
      ),
      title: Text(
        category.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: visible ? FontWeight.w600 : FontWeight.w400,
          color: visible
              ? AppColors.onScaffold(context)
              : AppColors.mutedText(context),
        ),
      ),
      trailing: Icon(
        visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        size: 18,
        color: visible ? color : AppColors.mutedText(context),
      ),
    );
  }
}
