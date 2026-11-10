import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 内置音乐平台的品牌色。
///
/// 榜单页、榜单设置、导入弹窗都要给平台一个稳定的颜色标识。这些色值
/// 曾经各写各的，同一个平台在两页里能差出半个色阶；集中到这里之后，
/// 换色只需要改一处。
///
/// 深色主题下把品牌色朝白色提一档：酷我紫、网易品红在深底上当文字色用时
/// 对比度不够，直接铺上去看不清。
Color platformBrandColor(BuildContext context, String platform) {
  final Color? base = switch (platform) {
    'kw' => const Color(0xFF6B3FA0),
    'tx' => const Color(0xFF2355C0),
    'wy' => const Color(0xFF9B3060),
    'kg' => const Color(0xFF2B7CD3),
    _ => null,
  };
  if (base == null) return AppColors.accentOf(context);
  return AppColors.isDark(context)
      ? Color.lerp(base, Colors.white, 0.30)!
      : base;
}
