import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';

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
          child: GlassSurface(
            style: AppGlassStyle.regular,
            backdrop: false,
            borderRadius: BorderRadius.circular(18),
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
