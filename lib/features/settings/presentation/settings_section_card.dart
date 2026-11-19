import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';

/// 分区卡片的圆角。
///
/// 卡片本身不再裁剪内容（见下面 `clipContent: false`），所以行内水波纹要按
/// 同一半径自己收边——两处必须一致，否则按下时涟漪会从卡片圆角外面探出来。
const BorderRadius kSettingsCardRadius = BorderRadius.all(Radius.circular(18));

/// 设置行标题的样式。
///
/// 开关行和导航行各有一处渲染，抽出来是为了两边不漂移：字号、字重、行高
/// 改一处就够，也不会出现同一页里两种标题观感。
TextStyle settingsRowTitleStyle(Color color) => TextStyle(
  fontSize: 14.5,
  fontWeight: FontWeight.w500,
  color: color,
);

/// 设置行副标题的样式。约束同 [_buildSwitchTile] / `_SettingsNavTile`：
/// 最多两行，超出省略，行高 1.3。
TextStyle settingsRowSubtitleStyle(Color color) => TextStyle(
  fontSize: 11.5,
  height: 1.3,
  color: color,
);

/// A titled glass block of settings rows.
///
/// Shared by the settings page and the settings search results so a result
/// looks exactly like the row it stands for.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          // 设置页一屏能同时出现四五张这种整宽卡片，背后又是纯色页面底。
          // 每张都挂一层 BackdropFilter 等于每次滚动都重算四五次全宽模糊，
          // 中端机上就是偶尔掉帧；关掉采样、直接混出实色，画面一模一样。
          //
          // 同理也不做圆角裁剪（clipContent: false）：卡片里的文字和开关都
          // 画不到圆角外面，唯一会溢出的水波纹由行自己的 customBorder 收边。
          // 为它每帧给整张卡生成一张覆盖率遮罩，正是这一页滑动掉帧的主因。
          child: GlassSurface(
            style: AppGlassStyle.regular,
            backdrop: false,
            clipContent: false,
            borderRadius: kSettingsCardRadius,
            border: Border.fromBorderSide(
              AppGlass.hairline(context, emphasized: false),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: AppColors.cardBorder(context),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 分区标题：强调色小竖条 + 一行标题 + 一条向右侧淡出的细线。
///
/// 之前是 12pt 的辅助色文字、紧贴左边（16pt，和卡片外缘对齐），在一屏
/// 七八个分区里几乎读不出层级——用户说得对：字太小，也太靠左。现在：
///
/// * 字号 13.5 + w700，颜色改成正文色（不是 45% 的灰）；
/// * 整体右移到 20pt，和卡片里的内容缩进对上，不再和卡片边缘抢对齐；
/// * 前面一根 3pt 的强调色竖条当「书签」，后面一条渐渐消失的细线把标题
///   和留白连起来，让标题成为一段的起点而不是一行注脚。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final line = AppColors.cardBorder(context);
    // 竖条跟着字号一起长：系统字体放到 2 倍时，固定 15pt 的竖条会缩成一小撇，
    // 和标题的行高对不上。
    final barHeight = MediaQuery.textScalerOf(context).scale(15);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 16, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: barHeight,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: AppColors.onScaffold(context).withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [line, line.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
