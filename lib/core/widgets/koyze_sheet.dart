import 'dart:math';

import 'package:flutter/material.dart';
import '../motion/motion_tokens.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// 统一的底部弹窗：从底部进入 + 轻微淡入/上浮 + scrim 平滑出现。
/// 所有 showModalBottomSheet 调用点统一替换，保证 Modal Motion 一致。
///
/// 默认铺磨砂玻璃。调用方若自己包了 [GlassSurface]（或需要完全透明），
/// 传 [backgroundColor] = [Colors.transparent] 并设 [frosted] = false。
///
/// 高度上限避开状态栏 / 灵动岛：顶边至少留出 [padding.top] + [_topGap]。
Future<T?> showKoyzeSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  bool enableDrag = true,
  bool frosted = true,
  bool useRootNavigator = true,
}) {
  final useGlass = frosted && backgroundColor != Colors.transparent;
  // 必须用调用方 context：sheet 内部会 removeTop，padding.top 会变成 0。
  final maxHeight = koyzeSheetMaxHeight(context);
  // 调用方没自己控制高度时，横屏仍会被 Material 限制在屏幕的 9/16，
  // 选项列表会直接底部溢出。这时改成内容多高就多高，放不下再滚动。
  final compactMenu = !isScrollControlled;
  final isDark = AppColors.isDark(context);
  // 弹层不铺满左右：贴边的面板读起来像一次页面跳转，而不是浮在当前页
  // 之上。手机留 12pt，宽屏由下面 constraints 的 640 上限自动居中留白。
  final side = MediaQuery.sizeOf(context).width >= 700 ? 0.0 : _sideGap;
  return showModalBottomSheet<T>(
    context: context,
    // 壳层迷你栏画在分支导航之上。默认走根导航；需要在当前
    // nested navigator 内关闭的调用点可显式关闭它。
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    // 深色下压得更重，浅色只轻压：否则白底页面会被压成灰。
    barrierColor: Colors.black.withValues(alpha: isDark ? 0.50 : 0.26),
    isScrollControlled: true,
    enableDrag: enableDrag,
    requestFocus: false,
    useSafeArea: true,
    constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
    // 圆角交给里面的 GlassSurface 画：面板左右也离屏了，四角必须都是圆的，
    // 只倒上面两个角会留下两条直边贴着页面。
    shape: const RoundedRectangleBorder(),
    sheetAnimationStyle: effectsAnimationStyle(
      duration: MotionDuration.sheet,
      reverseDuration: MotionDuration.sheetReverse,
      curve: MotionCurve.sheetIn,
      reverseCurve: MotionCurve.easeIn,
    ),
    builder: (context) {
      final built = builder(context);
      // 弹窗里的选项行统一一套排版：默认的 ListTile 是 16/56 的 Material
      // 尺寸，放在玻璃里偏松散；收紧到 15 号字、18pt 内边距后与设置页分组
      // 单元格一致。调用方显式写了样式的仍以自己为准。
      final baseTheme = Theme.of(context);
      final rowsTheme = baseTheme.copyWith(
        listTileTheme: ListTileThemeData(
          iconColor: AppColors.mutedText(context),
          textColor: AppColors.onScaffold(context),
          titleTextStyle: baseTheme.textTheme.titleSmall?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.onScaffold(context),
          ),
          subtitleTextStyle: baseTheme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: AppColors.mutedText(context),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          minVerticalPadding: 10,
        ),
        dividerTheme: DividerThemeData(
          color: AppColors.cardBorder(context),
          thickness: 0.6,
          space: 1,
        ),
      );
      final content = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motionDuration(context, MotionDuration.normal),
        curve: MotionCurve.iosSpring,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        ),
        child: compactMenu ? _CompactSheet(child: built) : built,
      );
      final themed = Theme(data: rowsTheme, child: content);
      final panel = useGlass
          ? GlassSurface(
              style: AppGlassStyle.regular,
              borderRadius: BorderRadius.circular(koyzeSheetRadius),
              color: backgroundColor,
              emphasized: true,
              // 面板四周都离屏，投影四向都要有，否则左右两侧会和页面糊在
              // 一起，看不出这是一张浮起来的卡片。
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.44)
                      : Colors.black.withValues(alpha: 0.14),
                  blurRadius: 32,
                  spreadRadius: -2,
                  offset: const Offset(0, -6),
                ),
              ],
              child: ClipRRect(
                borderRadius: BorderRadius.circular(koyzeSheetRadius),
                child: themed,
              ),
            )
          : themed;
      // 底部也留 10pt：只缩左右会让面板像被两条边夹住，底部贴边反而不像
      // 悬浮层。留出这一条后四角都是圆的，与搜索面板同一套「浮层」语言。
      return Padding(
        padding: EdgeInsets.fromLTRB(side, 0, side, _bottomGap),
        // 弹窗路由给的是松散约束（Align + ConstrainedBox），面板必须自己撑满
        // 可用宽度。否则内容本身不拉伸的弹层（只有一行文字的菜单）会缩成
        // 贴着屏幕中间的一条窄带。
        child: SizedBox(width: double.infinity, child: panel),
      );
    },
  );
}

/// 弹层圆角。与对话框（26）保持一致，切换弹窗类型时圆角不跳。
/// 调用方自己画面板（`frosted: false` + 自绘 [GlassSurface]）时也要用这个
/// 值，否则弹层家族里会混出两套圆角。
const double koyzeSheetRadius = 26;

/// 弹层里的动作行（播放 / 加入歌单 / 收藏 / 下载…）。
///
/// 不再直接用 ListTile：它的 56dp 行高和裸图标在玻璃面板上显得很"系统"。
/// 这里统一成 36dp 的圆角色块图标 + 15 号标签，行高收到 48，整组行读起来
/// 和设置里的选项面板是同一套语言。
class KoyzeSheetAction extends StatelessWidget {
  const KoyzeSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.tone,
    this.danger = false,
    this.selected = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;

  /// 图标色块的主色，默认取强调色。
  final Color? tone;
  final bool danger;

  /// 当前生效的选项：标签转强调色，字重加一档。
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = danger
        ? Theme.of(context).colorScheme.error
        : (tone ?? AppColors.accentOf(context));
    final primary = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    const radius = BorderRadius.all(Radius.circular(14));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(
                      alpha: AppColors.isDark(context) ? 0.18 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: danger || selected ? accent : primary,
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹层大标题行：一级标题 + 可选副标题 + 圆形关闭键。
///
/// 带封面的歌曲菜单用 [KoyzeSheetHeader]；选项面板（音质、搜索源、语言、
/// 睡眠定时）用这一套：标题走 headline 尺寸，副标题补一句当前状态，
/// 关掉面板的按钮是 36 的圆钮而不是一颗裸叉。
class KoyzeSheetTitle extends StatelessWidget {
  const KoyzeSheetTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.action,
    this.onClose,
    this.closeTooltip,
  });

  final String title;
  final String? subtitle;

  /// 需要自己刷新的副标题（例如倒计时），优先于 [subtitle]。
  final Widget? subtitleWidget;

  /// 标题右侧、关闭键左侧的附加动作（例如"新建歌单"）。
  final Widget? action;
  final VoidCallback? onClose;

  /// 关闭键的提示文案（无障碍朗读用）。
  final String? closeTooltip;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.mutedText(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onScaffold(context),
                    fontSize: 21,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 3),
                  subtitleWidget!,
                ] else if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: muted,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
          if (onClose != null) ...[
            const SizedBox(width: 10),
            KoyzeSheetClose(onTap: onClose!, tooltip: closeTooltip),
          ],
        ],
      ),
    );
  }
}

/// 弹层右上角的圆形关闭键，与标题行、选项面板共用。
class KoyzeSheetClose extends StatelessWidget {
  const KoyzeSheetClose({super.key, required this.onTap, this.tooltip});

  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      type: MaterialType.transparency,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.fill(context),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.close_rounded,
            size: 19,
            color: AppColors.mutedText(context),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 顶部的拖动把手。Origo 的每个弹层都有一条 36×4 的浅色横条，
/// 它比任何阴影都更能说明"这是一张可以往下推走的浮层"。
class KoyzeSheetGrabber extends StatelessWidget {
  const KoyzeSheetGrabber({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: margin ?? const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        // 深色玻璃上 0.32 的灰几乎看不见，把手要稍微实一点才读得出"可拖动"。
        color: AppColors.secondaryText(
          context,
        ).withValues(alpha: AppColors.isDark(context) ? 0.44 : 0.30),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

/// 弹层标题行：封面（或图标）+ 主副标题 + 关闭键。
class KoyzeSheetHeader extends StatelessWidget {
  const KoyzeSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.artwork,
    this.icon,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final String? artwork;
  final IconData? icon;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    final hasCover = artwork != null && artwork!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KoyzeSheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 40,
                  height: 40,
                  color: AppColors.accentOf(context).withValues(alpha: 0.16),
                  child: hasCover
                      ? Image.network(
                          artwork!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            icon ?? Icons.music_note_rounded,
                            size: 19,
                            color: primary,
                          ),
                        )
                      : Icon(
                          icon ?? Icons.music_note_rounded,
                          size: 19,
                          color: primary,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primary,
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onClose != null) KoyzeSheetClose(onTap: onClose!),
            ],
          ),
        ),
      ],
    );
  }
}

/// 弹层里分组之间的细分隔。
const SizedBox koyzeSheetActionGap = SizedBox(height: 6);

/// 左右留白：手机上面板不贴边，宽屏由 640 的宽度上限居中留出。
const double _sideGap = 12;

/// 底部留白：让四角都能看见圆角，而不是被屏幕下沿切平。
const double _bottomGap = 10;

/// 弹窗可用高度：屏幕高度减去状态栏（含灵动岛）再留一点空隙。
/// [context] 必须是弹窗弹出之前的页面；sheet 内部 padding.top 会被清掉。
double koyzeSheetMaxHeight(BuildContext context) {
  final media = MediaQuery.of(context);
  final topInset = max(media.padding.top, media.viewPadding.top);
  return max(media.size.height - topInset - _topGap, 200);
}

const double _topGap = 16;

/// 短菜单按内容收缩；超过可用高度时在弹窗内部滚动，而不是底部溢出。
class _CompactSheet extends StatelessWidget {
  const _CompactSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(child: child);
  }
}
