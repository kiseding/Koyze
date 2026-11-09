import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../l10n/app_strings.dart';

/// 用户条款与免责声明。
///
/// 这是一份供查阅的文档，不是启动时的一道门：应用启动不渲染它，也不拦截
/// 任何页面，入口只留在设置的最后一个分区。改动文案前请先核对产品实际
/// 行为，尤其是第三方脚本与数据处理这两节，写得不到位比不写更麻烦。
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final secondary = AppColors.secondaryText(context);
    final bodyStyle = TextStyle(fontSize: 13.5, height: 1.85, color: secondary);

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
          s.termsTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.onScaffold(context),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 44),
            children: [
              Text(
                s.termsUpdated,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  letterSpacing: 0.3,
                  color: AppColors.mutedText(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(s.termsPreamble, style: bodyStyle),
              for (final section in s.termsSections) ...[
                const SizedBox(height: 26),
                Text(
                  section.title,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onScaffold(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(section.body, style: bodyStyle),
              ],
              const SizedBox(height: 30),
              Container(height: 1, color: AppColors.cardBorder(context)),
              const SizedBox(height: 16),
              Text(
                s.termsFooter,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: AppColors.mutedText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
