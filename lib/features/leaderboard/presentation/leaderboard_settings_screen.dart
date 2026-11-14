import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koyze/core/music_source/platform/music_platform.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/core/theme/platform_colors.dart';
import 'package:koyze/features/leaderboard/presentation/leaderboard_provider.dart';
import '../../../l10n/app_strings.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/pressable.dart';

/// 打开榜单设置弹窗。
///
/// 设置项按平台分页，一次只铺一个平台，四十多个榜不会挤成一条长列表。
/// 高度给到屏高的 0.76：一屏能看到六七个榜，又不会把榜单页整个盖住。
Future<void> showLeaderboardSettingsSheet(BuildContext context) {
  final media = MediaQuery.sizeOf(context);
  final maxHeight = koyzeSheetMaxHeight(context);
  // 上下都夹一次：矮屏不至于只剩两行，平板不至于变成一张空桌面。
  final desired = math.max(460.0, math.min(680.0, media.height * 0.76));
  return showKoyzeSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SizedBox(
      height: math.min(desired, maxHeight - 12),
      child: const LeaderboardSettingsSheet(),
    ),
  );
}

/// 榜单设置弹窗：标题 + 平台分页 + 该平台的榜单开关。
class LeaderboardSettingsSheet extends ConsumerWidget {
  const LeaderboardSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(leaderboardCategoriesProvider).valueOrNull ??
        const <LeaderboardCategory>[];
    final data = _LeaderboardSettingsData.from(
      categories,
      ref.watch(leaderboardLayoutProvider),
    );
    return Column(
      children: [
        KoyzeSheetTitle(
          title: S.of(context).chartSettings,
          // 副标题跟着「全部显示」与关闭键抢宽度，用短句而不是
          // 「共 N 个榜单，已显示 M 个」：手机上后者会被截成省略号。
          subtitle: data.totalCharts == 0
              ? null
              : S
                    .of(context)
                    .chartVisibilityRatio(data.visibleCharts, data.totalCharts),
          onClose: () => Navigator.pop(context),
          closeTooltip: S.of(context).close,
          action: _RestoreAllButton(
            onPressed: () =>
                ref.read(leaderboardLayoutProvider.notifier).restoreAll(),
          ),
        ),
        const Expanded(child: LeaderboardSettingsView()),
      ],
    );
  }
}

/// 榜单设置正文：平台分页 + 平台总开关 + 榜单列表。
///
/// 弹窗与独立页面共用这一块，两者只是外壳不同；分成两套实现的话，
/// 同一个开关在弹窗里和页面里的行为迟早会分叉。
class LeaderboardSettingsView extends ConsumerStatefulWidget {
  const LeaderboardSettingsView({super.key});

  @override
  ConsumerState<LeaderboardSettingsView> createState() =>
      _LeaderboardSettingsViewState();
}

class _LeaderboardSettingsViewState
    extends ConsumerState<LeaderboardSettingsView> {
  /// 当前查看的平台。为空时落到第一个平台——布局数据是异步加载的，
  /// 首帧还拿不到平台列表，不能把默认值写死在初始化里。
  String? _platform;

  /// 默认布局要等当前帧建完才能生成：`ensureDefaultLayout` 会写 provider
  /// 状态，在 build 期间写会被 Riverpod 拦下来。
  ///
  /// 设置页从首页快捷方式进来时，榜单页可能还没打开过，布局就是空的；
  /// 没有这一步，开关点了也不会留下任何记录。
  bool _layoutScheduled = false;

  void _scheduleDefaultLayout(List<LeaderboardCategory> categories) {
    if (_layoutScheduled) return;
    _layoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (!mounted) return;
      ref
          .read(leaderboardLayoutProvider.notifier)
          .ensureDefaultLayout(categories);
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(leaderboardCategoriesProvider);
    final categories =
        categoriesAsync.valueOrNull ?? const <LeaderboardCategory>[];
    final layout = ref.watch(leaderboardLayoutProvider);
    if (layout.isEmpty && categories.isNotEmpty) {
      _scheduleDefaultLayout(categories);
    }
    final data = _LeaderboardSettingsData.from(categories, layout);

    if (categories.isEmpty) {
      if (categoriesAsync.hasError) {
        return Center(
          child: Text(
            S.of(context).loadSongsFailed,
            style: TextStyle(color: AppColors.mutedText(context)),
          ),
        );
      }
      if (categoriesAsync.isLoading) {
        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: AppLoadingIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.accentOf(context),
              ),
            ),
          ),
        );
      }
      return Center(
        child: Text(
          S.of(context).noChartData,
          style: TextStyle(color: AppColors.mutedText(context)),
        ),
      );
    }

    final selected = data.platforms.contains(_platform)
        ? _platform!
        : data.platforms.first;

    return Column(
      children: [
        const SizedBox(height: 2),
        _PlatformTabs(
          data: data,
          selected: selected,
          onSelect: (platform) => setState(() => _platform = platform),
        ),
        const SizedBox(height: 10),
        Expanded(child: _buildPlatformPanel(context, data, selected)),
      ],
    );
  }

  Widget _buildPlatformPanel(
    BuildContext context,
    _LeaderboardSettingsData data,
    String platform,
  ) {
    final charts = data.grouped[platform] ?? const <LeaderboardCategory>[];
    final platformHidden = data.isPlatformHidden(platform);
    final color = platformBrandColor(context, platform);
    final visible = charts
        .where((chart) => !data.isChartHidden(chart.id))
        .length;
    final notifier = ref.read(leaderboardLayoutProvider.notifier);
    final muted = AppColors.mutedText(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
          decoration: BoxDecoration(
            color: AppColors.fill(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.cardBorder(context),
              width: 0.6,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_platformIcon(platform), color: color, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.of(context).platformName(platform),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: AppColors.onScaffold(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      S
                          .of(context)
                          .chartVisibilityRatio(visible, charts.length),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.2,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              FxSwitch(
                value: !platformHidden,
                accent: color,
                onChanged: (enabled) =>
                    notifier.setPlatformVisible(platform, enabled),
              ),
            ],
          ),
        ),
        if (platformHidden) ...[
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.visibility_off_rounded, size: 14, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    S
                        .of(context)
                        .hiddenUntil(S.of(context).platformName(platform)),
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        // 平台关掉时列表变成只读预览：还能看见里面有哪些榜，但点不动。
        // 直接整块隐藏会让用户以为榜单被删了。
        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          opacity: platformHidden ? 0.4 : 1,
          child: IgnorePointer(
            ignoring: platformHidden,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.fill(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.cardBorder(context),
                  width: 0.6,
                ),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < charts.length; index++) ...[
                    _CategoryVisibilityTile(
                      category: charts[index],
                      color: color,
                      visible: !data.isChartHidden(charts[index].id),
                      onChanged: (visible) {
                        if (visible) {
                          notifier.restoreItem('category:${charts[index].id}');
                        } else {
                          notifier.hideCategory(charts[index].id);
                        }
                      },
                    ),
                    if (index < charts.length - 1)
                      Divider(
                        height: 1,
                        indent: 46,
                        endIndent: 14,
                        color: AppColors.cardBorder(context),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  S.of(context).chartSettingsHint,
                  style: TextStyle(fontSize: 11.5, height: 1.35, color: muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 平台分页。横向滚动而不是等分：平台数量随音源增减，等分会在加到第五个
/// 平台时把每个名字都挤成省略号。
class _PlatformTabs extends StatelessWidget {
  const _PlatformTabs({
    required this.data,
    required this.selected,
    required this.onSelect,
  });

  final _LeaderboardSettingsData data;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: data.platforms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final platform = data.platforms[index];
          final active = platform == selected;
          final hidden = data.isPlatformHidden(platform);
          final color = platformBrandColor(context, platform);
          final isDark = AppColors.isDark(context);
          return Pressable(
            borderRadius: BorderRadius.circular(13),
            selected: active,
            onTap: () => onSelect(platform),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: active
                    ? color.withValues(alpha: isDark ? 0.20 : 0.11)
                    : AppColors.fill(context),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: active
                      ? color.withValues(alpha: 0.45)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: hidden ? AppColors.mutedText(context) : color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    S.of(context).platformName(platform),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.1,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? color : AppColors.secondaryText(context),
                    ),
                  ),
                  if (hidden) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.visibility_off_rounded,
                      size: 12,
                      color: AppColors.mutedText(context),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 单条榜单的显隐开关。
///
/// 左侧是自绘的勾选方块，右侧只留一个眼睛：Material 的 Checkbox 在玻璃底
/// 上自带一圈灰色圆角，和这里的圆角卡片不是一个语言。
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
    final onColor = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    return Pressable(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!visible),
      semanticLabel: category.name,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: visible ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: visible ? color : muted.withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
              child: visible
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 14,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.25,
                  fontWeight: visible ? FontWeight.w600 : FontWeight.w400,
                  color: visible ? onColor : muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 16,
              color: visible ? color : muted.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标题行右侧的「全部显示」。做成胶囊而不是文字按钮：
/// 它在标题行里是次要动作，但不该小到看不见。
class _RestoreAllButton extends StatelessWidget {
  const _RestoreAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.done_all_rounded, size: 15),
      // 字号写在 label 上而不是 styleFrom(textStyle:)：后者会整体替换按钮
      // 的文本样式，把主题字体族一起丢掉。
      label: Text(
        S.of(context).showAll,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: accent,
        backgroundColor: accent.withValues(alpha: 0.10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
      ),
    );
  }
}

/// 设置页要用到的分组结果与统计，避免弹窗标题和正文各算一遍。
class _LeaderboardSettingsData {
  const _LeaderboardSettingsData({
    required this.platforms,
    required this.grouped,
    required this.hiddenByKey,
    required this.visibleCharts,
    required this.totalCharts,
  });

  factory _LeaderboardSettingsData.from(
    List<LeaderboardCategory> categories,
    List<LeaderboardLayoutItem> layout,
  ) {
    final grouped = <String, List<LeaderboardCategory>>{};
    for (final category in categories) {
      grouped.putIfAbsent(category.platform ?? 'other', () => []).add(category);
    }
    // 布局顺序优先，其余平台追加在末尾——和榜单页的分段顺序保持一致。
    final platforms = <String>[
      ...layout
          .where((item) => item.isPlatform)
          .map((item) => item.platformId!)
          .where(grouped.containsKey),
      ...grouped.keys.where(
        (key) =>
            !layout.any((item) => item.isPlatform && item.platformId == key),
      ),
    ];
    final hiddenByKey = <String, bool>{
      for (final item in layout) item.key: item.hidden,
    };
    var total = 0;
    var visible = 0;
    for (final platform in platforms) {
      for (final category in grouped[platform]!) {
        total++;
        if (!(hiddenByKey['category:${category.id}'] ?? false)) visible++;
      }
    }
    return _LeaderboardSettingsData(
      platforms: platforms,
      grouped: grouped,
      hiddenByKey: hiddenByKey,
      visibleCharts: visible,
      totalCharts: total,
    );
  }

  final List<String> platforms;
  final Map<String, List<LeaderboardCategory>> grouped;
  final Map<String, bool> hiddenByKey;
  final int visibleCharts;
  final int totalCharts;

  bool isPlatformHidden(String platform) =>
      hiddenByKey['platform:$platform'] ?? false;

  bool isChartHidden(String categoryId) =>
      hiddenByKey['category:$categoryId'] ?? false;
}

IconData _platformIcon(String platform) {
  switch (platform) {
    case 'tx':
      return Icons.music_note_rounded;
    case 'kw':
      return Icons.graphic_eq_rounded;
    case 'wy':
      return Icons.album_rounded;
    case 'kg':
      return Icons.headphones_rounded;
    default:
      return Icons.library_music_rounded;
  }
}

/// 榜单设置的独立页面。
///
/// 首页快捷方式仍以页面形式打开；内容和弹窗共用 [LeaderboardSettingsView]，
/// 两种入口看到的是同一套开关与分组。
class LeaderboardSettingsScreen extends ConsumerWidget {
  const LeaderboardSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            tooltip: S.of(context).back,
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            S.of(context).chartSettings,
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
              label: Text(S.of(context).showAll),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentOf(context),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 4,
          ),
          child: const LeaderboardSettingsView(),
        ),
      ),
    );
  }
}
