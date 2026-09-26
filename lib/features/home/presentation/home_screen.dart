import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_strings.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/frosted_tab_header.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/root_shell_layout.dart';
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
            final isLandscapeShell = RootShellLayout.usesSideNavigationOf(
              context,
            );
            final headerExtent = isLandscapeShell
                ? 0.0
                : FrostedTabHeader.extent(context);

            return Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      isWide ? 0 : 16,
                      headerExtent == 0 ? 16 : headerExtent + 8,
                      isWide ? 0 : 16,
                      12 + RootShellLayout.obscuredBottomOf(context),
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
                          _buildQuickSectionTitle(
                            context,
                            S.of(context).shortcuts,
                          ),
                          const SizedBox(height: 12),
                          _buildQuickGrid(context, ref, columns, quickIds),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isLandscapeShell)
                  RootHeaderPublisher(
                    index: 0,
                    title: 'Koyze',
                    titleKey: _brandKey,
                    actions: [
                      FrostedHeaderButton(
                        icon: Icons.tune_rounded,
                        semanticLabel: S.of(context).heroCardSettingsAction,
                        onTap: () => _showHeroCardSettings(context),
                      ),
                    ],
                  )
                else
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
                          semanticLabel: S.of(context).heroCardSettingsAction,
                          onTap: () => _showHeroCardSettings(context),
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
                S.of(context).searchSongsHint,
                style: TextStyle(color: muted, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSectionTitle(BuildContext context, String title) {
    final titleStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AppColors.onScaffold(context),
    );
    return Row(
      children: [
        Text(title, style: titleStyle),
        const Spacer(),
        Pressable(
          semanticLabel: S.of(context).shortcutSettings,
          onTap: () => _showQuickSettings(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CustomPaint(
                painter: _QuickEditPenPainter(
                  color: AppColors.secondaryText(context),
                ),
              ),
            ),
          ),
        ),
      ],
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

  Widget _sheetHeader(
    BuildContext context, {
    required String title,
    required String closeLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.onScaffold(context),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FxIconButton(
            tooltip: closeLabel,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showHeroCardSettings(BuildContext context) {
    final maxHeight = koyzeSheetMaxHeight(context);
    showKoyzeSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHeader(
                context,
                title: S.of(context).heroCardSettings,
                closeLabel: S.of(context).closeHeroCardSettings,
              ),
              const HomeHeroCardSettings(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickSettings(BuildContext context) {
    final maxHeight = koyzeSheetMaxHeight(context);
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
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHeader(
                  context,
                  title: S.of(context).shortcutSettings,
                  closeLabel: S.of(context).closeShortcutSettings,
                ),
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
                          S.of(context).quickTitle(feature.id),
                          style: TextStyle(
                            color: active
                                ? AppColors.onScaffold(context)
                                : AppColors.mutedText(context),
                          ),
                        ),
                        subtitle: Text(
                          S.of(context).quickSubtitle(feature.id),
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
                  S.of(context).quickTitle(entry.id),
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
                  S.of(context).quickSubtitle(entry.id),
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

/// 16pt 实心圆角铅笔，笔画体量贴近顶栏 [FrostedHeaderButton] 的 tune 图标。
/// 高度锁在标题字号内，避免撑高「快捷功能」这一行。
class _QuickEditPenPainter extends CustomPainter {
  const _QuickEditPenPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 24, side / 24);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final pencil = Path()..fillType = PathFillType.evenOdd;
    pencil.moveTo(3.6, 21.0);
    pencil.lineTo(4.0, 14.6);
    pencil.lineTo(14.8, 3.8);
    pencil.cubicTo(15.55, 3.05, 16.75, 3.05, 17.5, 3.8);
    pencil.lineTo(20.2, 6.5);
    pencil.cubicTo(20.95, 7.25, 20.95, 8.45, 20.2, 9.2);
    pencil.lineTo(9.4, 20.0);
    pencil.close();
    // 笔尖三角缺口，16pt 下也能看出是笔而不是楔块。
    pencil.moveTo(5.2, 19.15);
    pencil.lineTo(5.45, 16.2);
    pencil.lineTo(7.85, 18.85);
    pencil.close();
    // 笔杆箍：对角开一条缝，体量接近 tune 滑块的圆角横档。
    pencil.moveTo(13.55, 6.35);
    pencil.lineTo(17.65, 10.45);
    pencil.lineTo(16.35, 11.75);
    pencil.lineTo(12.25, 7.65);
    pencil.close();
    canvas.drawPath(pencil, fill);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _QuickEditPenPainter oldDelegate) =>
      oldDelegate.color != color;
}
