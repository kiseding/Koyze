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
import '../../../core/widgets/koyze_sheet.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../../core/motion/list_entrance.dart';
import '../../../core/widgets/origo_chrome.dart';

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
            final height = constraints.maxHeight;
            final isWide = width >= 720;
            final contentWidth = shellContentWidth(width);
            // Landscape rows have far less height than width; a stacked
            // 218-point hero plus a shortcut grid would scroll immediately.
            final isLandscape =
                width > height * 1.12 && height < 620 && width >= 560;
            final isLandscapeShell = RootShellLayout.usesSideNavigationOf(
              context,
            );
            final headerExtent = isLandscapeShell
                ? 0.0
                : FrostedTabHeader.extent(context);
            final obscured = RootShellLayout.obscuredBottomOf(context);

            return Stack(
              children: [
                Positioned.fill(
                  child: OrigoAmbientBackdrop(
                    leadingColor: AppColors.accentOf(context),
                    trailingColor: Theme.of(context).colorScheme.secondary,
                    child: const SizedBox.expand(),
                  ),
                ),
                if (isLandscape)
                  _buildLandscapeBody(
                    context,
                    ref,
                    contentWidth: contentWidth,
                    headerExtent: headerExtent,
                    obscuredBottom: obscured,
                    quickIds: quickIds,
                  )
                else
                  _buildPortraitBody(
                    context,
                    ref,
                    contentWidth: contentWidth,
                    headerExtent: headerExtent,
                    obscuredBottom: obscured,
                    isWide: isWide,
                    columns: isWide ? 4 : 2,
                    quickIds: quickIds,
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

  /// Portrait: search, hero stage, shortcut grid, all in one scroll column.
  Widget _buildPortraitBody(
    BuildContext context,
    WidgetRef ref, {
    required double contentWidth,
    required double headerExtent,
    required double obscuredBottom,
    required bool isWide,
    required int columns,
    required List<String> quickIds,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          isWide ? 0 : 16,
          headerExtent == 0 ? 24 : headerExtent + 12,
          isWide ? 0 : 16,
          28 + obscuredBottom,
        ),
        child: SizedBox(
          width: contentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListEntrance(index: 0, child: _buildSearchBar(context)),
              const SizedBox(height: 20),
              const ListEntrance(index: 1, child: HomeHeroCard()),
              const SizedBox(height: 24),
              ListEntrance(
                index: 2,
                child: _buildQuickSectionTitle(
                  context,
                  S.of(context).shortcuts,
                ),
              ),
              const SizedBox(height: 12),
              _buildQuickGrid(context, ref, columns, quickIds),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Landscape: hero on the left, search plus shortcuts on the right. The hero
  /// fills the row height instead of pinning 218 points, and the shortcut list
  /// scrolls on its own so the page itself never scrolls.
  Widget _buildLandscapeBody(
    BuildContext context,
    WidgetRef ref, {
    required double contentWidth,
    required double headerExtent,
    required double obscuredBottom,
    required List<String> quickIds,
  }) {
    final top = headerExtent == 0 ? 18.0 : headerExtent + 8;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top, 20, 20 + obscuredBottom),
        child: LayoutBuilder(
          builder: (context, outer) {
            // 两栏放进同一个高度盒子：整行撑满窗口时 hero 会被拉成一张
            // 390×475 的巨幅，收在 340 以内再顶对齐，左右两栏的顶边、底边
            // 才会落在同一条水平线上。
            final rowHeight = min(
              outer.maxHeight,
              (MediaQuery.sizeOf(context).height * 0.72).clamp(240.0, 340.0),
            );
            return SizedBox(
              width: contentWidth,
              height: rowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: ListEntrance(
                      index: 0,
                      child: const HomeHeroCard(height: null),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListEntrance(index: 0, child: _buildSearchBar(context)),
                        const SizedBox(height: 16),
                        ListEntrance(
                          index: 1,
                          child: _buildQuickSectionTitle(
                            context,
                            S.of(context).shortcuts,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) {
                              // Eight entries over two columns is four rows. A
                              // fixed 52pt tile leaves a ~100pt hole at the
                              // bottom of a tablet's right column while the hero
                              // next to it runs the full 340 — the two columns
                              // stop ending on the same line. Spread the tiles
                              // over whatever height is actually available.
                              const spacing = 8.0;
                              const bottomFade = 14.0;
                              // Two columns everywhere. A third column does fit
                              // all eight entries on a landscape phone, but each
                              // tile then has ~70pt of text width and English
                              // captions come back as "Local m…", "Listenin…".
                              // Keeping two columns means the list scrolls; the
                              // fade at the bottom is what says so.
                              const columns = 2;
                              final rows = (quickIds.length / columns).ceil();
                              final tileHeight =
                                  ((box.maxHeight -
                                              bottomFade -
                                              (rows - 1) * spacing) /
                                          rows)
                                      .clamp(52.0, 78.0);
                              // A landscape window is too short for eight
                              // shortcut tiles, so the list always ends mid-card.
                              // Fade the last few points instead of slicing a
                              // card in half.
                              return ShaderMask(
                                shaderCallback: (rect) => const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white,
                                    Colors.white,
                                    Colors.transparent,
                                  ],
                                  stops: [0, 0.9, 1],
                                ).createShader(rect),
                                blendMode: BlendMode.dstIn,
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.only(
                                    bottom: bottomFade,
                                  ),
                                  // Two columns instead of one: the right half of
                                  // a landscape window is ~590pt wide, so a
                                  // single column of tiles left half the row
                                  // blank and still ended after three and a half
                                  // of the eight entries.
                                  child: _buildQuickGrid(
                                    context,
                                    ref,
                                    columns,
                                    quickIds,
                                    dense: true,
                                    tileHeight: tileHeight,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    // mutedText 在白玻璃上只有 2.5:1，15pt 的占位符读起来发灰；
    // 提到 secondaryText，和卡片副标题用同一档。
    final hint = AppColors.secondaryText(context);
    return Pressable(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openSearchSheet(context),
      child: OrigoChromeSurface(
        borderRadius: BorderRadius.circular(18),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        accent: AppColors.accentOf(context),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: hint, size: 21),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                S.of(context).searchSongsHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hint,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, color: hint, size: 17),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSectionTitle(BuildContext context, String title) {
    // Section label, not a second page title: smaller, tracked out, muted.
    final titleStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: AppColors.secondaryText(context),
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
    List<String> quickIds, {
    bool dense = false,
    double? tileHeight,
  }) {
    final entries = [
      for (final id in quickIds)
        homeQuickFeatures.firstWhere((entry) => entry.id == id),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = dense ? 8.0 : 10.0;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var index = 0; index < entries.length; index++)
              SizedBox(
                width: tileWidth,
                child: ListEntrance(
                  key: ValueKey('quick-${entries[index].id}'),
                  index: index,
                  child: _QuickEntryCard(
                    entry: entries[index],
                    dense: dense,
                    tileHeight: tileHeight,
                  ),
                ),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KoyzeSheetGrabber(),
        KoyzeSheetTitle(
          title: title,
          closeTooltip: closeLabel,
          onClose: () => Navigator.pop(context),
        ),
      ],
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

  /// Landscape has roughly 190 points for the whole list; dropping the
  /// caption fits four tiles instead of two and a half.
  final bool dense;

  /// 覆盖默认行高。平板横屏的右栏放得下更高的卡，撑满后与左侧 hero 齐底。
  final double? tileHeight;

  const _QuickEntryCard({
    required this.entry,
    this.dense = false,
    this.tileHeight,
  });

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
    // The whole tile is tappable, so the trailing arrow only stole width from
    // the label — at 2 columns it was the reason "Local music" clipped.
    //
    // Height is fixed rather than content-driven: the tiles live in a Wrap, so
    // a two-line caption on one card would otherwise make its whole run taller
    // and leave the neighbours floating against different baselines.
    return SizedBox(
      height: tileHeight ?? (dense ? 52 : 68),
      child: OrigoChromeSurface(
        borderRadius: BorderRadius.circular(18),
        padding: EdgeInsets.fromLTRB(11, dense ? 8 : 10, 11, dense ? 8 : 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: color.withValues(alpha: 0.20)),
              ),
              child: Icon(entry.icon, color: color, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    S.of(context).quickTitle(entry.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -0.2,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  if (!dense) ...[
                    const SizedBox(height: 3),
                    // Two lines: at 2 columns the caption only gets ~106pt, and
                    // every longer English label ("Tasks and progress") was
                    // cut in the middle of a word.
                    Text(
                      S.of(context).quickSubtitle(entry.id),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.8,
                        height: 1.16,
                        letterSpacing: 0,
                        // mutedText is 45% black in the light theme — at 9.8pt
                        // that lands around 2.5:1 on a white card.
                        color: AppColors.secondaryText(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
