import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/frosted_tab_header.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/search_sheet.dart';
import '../../../core/widgets/sleep_timer_sheet.dart';
import '../../settings/presentation/settings_provider.dart';
import 'home_hero_card.dart';
import 'home_quick_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../core/widgets/fx_switch.dart';

/// 首页：搜索入口 + 可切换的歌单大卡片 + 快捷功能。
/// 竖屏单列、大屏居中并自适应列数，底部导航由 MainScaffold 提供。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// 定位首页标题文字，供搜索弹窗计算顶部高度。
  final GlobalKey _brandKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final quickSettings = ref.watch(homeQuickSettingsProvider);
    final quickIds = [
      for (final id in quickSettings.order)
        if (quickSettings.enabled.contains(id)) id,
    ];

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= 720;
            final contentWidth = isWide ? min(width * 0.82, 900.0) : width;
            final columns = isWide ? 4 : 2;
            final headerExtent = FrostedTabHeader.extent(context);

            return Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      isWide ? 0 : 16,
                      headerExtent + 8,
                      isWide ? 0 : 16,
                      12,
                    ),
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSearchBar(context),
                          const SizedBox(height: 20),
                          const HomeHeroCard(),
                          const SizedBox(height: 24),
                          _buildQuickSectionTitle(context, '快捷功能'),
                          const SizedBox(height: 12),
                          _buildQuickGrid(context, ref, columns, quickIds),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FrostedTabHeader(
                    title: 'Koyze',
                    titleKey: _brandKey,
                    leadingIcon: Icons.home_rounded,
                    actions: [
                      FrostedHeaderButton(
                        icon: Icons.tune_rounded,
                        semanticLabel: '设置快捷功能',
                        onTap: () => _showQuickSettings(context),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openSearchSheet(BuildContext context) {
    // 弹窗顶部对齐首页 Koyze 文字顶部上方 3px。
    double topInset = 0;
    final box = _brandKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.attached) {
      topInset = box.localToGlobal(Offset.zero).dy - 3;
    }
    showSearchSheet(context, topInset: topInset > 0 ? topInset : 0);
  }

  /// 搜索条占一行：点击弹出搜索弹窗（滑入动画，2/3 时弹输入法）。
  Widget _buildSearchBar(BuildContext context) {
    final muted = AppColors.mutedText(context);
    final border = AppColors.cardBorder(context);
    return Pressable(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openSearchSheet(context),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.miniBar(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: muted, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '搜索歌曲、歌手、歌单...',
                style: TextStyle(color: muted, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.onScaffold(context),
      ),
    );
  }

  Widget _buildQuickGrid(
    BuildContext context,
    WidgetRef ref,
    int columns,
    List<String> quickIds,
  ) {
    final entries = [
      for (final id in quickIds)
        homeQuickFeatures.firstWhere((entry) => entry.id == id),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final entry in entries)
              SizedBox(
                width: tileWidth,
                child: _QuickEntryCard(entry: entry),
              ),
          ],
        );
      },
    );
  }

  void _showQuickSettings(BuildContext context) {
    showKoyzeSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(homeQuickSettingsProvider);
          final enabled = settings.enabled;
          final notifier = ref.read(homeQuickSettingsProvider.notifier);
          final order = settings.order;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '快捷功能设置',
                          style: TextStyle(
                            color: AppColors.onScaffold(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FxIconButton(
                        tooltip: '关闭快捷功能设置',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const HomeHeroCardSettings(),
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: order.length,
                    onReorderItem: notifier.reorder,
                    itemBuilder: (context, index) {
                      final feature = homeQuickFeatures.firstWhere(
                        (item) => item.id == order[index],
                      );
                      final active = enabled.contains(feature.id);
                      return ListTile(
                        key: ValueKey(feature.id),
                        leading: Icon(feature.icon, color: feature.color),
                        title: Text(
                          feature.title,
                          style: TextStyle(
                            color: active
                                ? AppColors.onScaffold(context)
                                : AppColors.mutedText(context),
                          ),
                        ),
                        subtitle: Text(
                          feature.subtitle,
                          style: TextStyle(
                            color: AppColors.mutedText(context),
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FxSwitch(
                              value: active,
                              onChanged: (value) =>
                                  notifier.setEnabled(feature.id, value),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: AppColors.mutedText(context),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 快捷功能特殊交互。
class _QuickEntryCard extends ConsumerWidget {
  final HomeQuickFeature entry;

  const _QuickEntryCard({required this.entry});

  void _toggleTheme(WidgetRef ref) {
    final current = ref.read(themeModeProvider);
    final next = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    ref.read(themeModeProvider.notifier).setThemeMode(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = entry.color;
    final isPageEntry = entry.action == null && entry.route.isNotEmpty;
    return Pressable(
      borderRadius: BorderRadius.circular(14),
      captureExpandRect: isPageEntry,
      onTap: () {
        switch (entry.action) {
          case HomeQuickAction.sleepTimer:
            showSleepTimerSheet(context, ref);
          case HomeQuickAction.themeToggle:
            _toggleTheme(ref);
          case null:
            if (entry.route == 'localPlaylist' ||
                entry.route == 'favoritesPlaylist' ||
                entry.route == 'recentPlaylist') {
              context.pushNamed(
                'playlistDetail',
                pathParameters: {
                  'playlistId': switch (entry.route) {
                    'localPlaylist' => 'local',
                    'favoritesPlaylist' => 'favorites',
                    _ => 'recent',
                  },
                },
              );
            } else {
              context.push(entry.route);
            }
        }
      },
      child: _buildCardBody(context, ref, color),
    );
  }

  Widget _buildCardBody(BuildContext context, WidgetRef ref, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(entry.icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onScaffold(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: AppColors.mutedText(context),
            size: 18,
          ),
        ],
      ),
    );
  }
}
