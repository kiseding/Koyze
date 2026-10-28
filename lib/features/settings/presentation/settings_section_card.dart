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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              // 与首页「快捷方式」、歌单页「自定义歌单」同一档：
              // 分区标签是路标，不是注脚。10pt 加 1.2 字距在中文字面下
              // 几乎读不出字形，45% 黑的对比度也不够。
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.secondaryText(context),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: GlassSurface(
            style: AppGlassStyle.regular,
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
