import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 内置音乐平台的品牌色。
///
/// 榜单页、榜单设置、导入弹窗都要给平台一个稳定的颜色标识。这些色值
/// 曾经各写各的，同一个平台在两页里能差出半个色阶；集中到这里之后，
/// 换色只需要改一处。
///
/// 一家平台在这里有两个颜色，分工不能混：
///
/// * [platformBrandColor]：**墨色**。画在页面底色之上——小圆点、图标、
///   浅色底上的文字。深色主题下朝白色提一档，否则深蓝深红压在黑底上看不清。
/// * [platformBrandFill]：**底色**。白字永远压在它上面（榜单页的平台胶囊），
///   所以不跟主题走，且统一压深到与白色 ≥ 4.5:1。
///
/// 第二个颜色不是多余的：品牌原色直接铺白字读不出来。四家的原色对白字的
/// 对比度分别是——QQ 绿 #31C27C 约 2.3:1、酷我黄 #FFC800 约 1.6:1、
/// 网易红 #C20C0C 约 6.2:1、酷狗蓝 #00A0E9 约 3.0:1。前两个必须压深，
/// 后两个本来就够，保持原色即可。
Color platformBrandColor(BuildContext context, String platform) {
  final base = platformBrandFill(platform);
  return AppColors.isDark(context)
      ? Color.lerp(base, Colors.white, 0.32)!
      : base;
}

/// 品牌原色，**只能做装饰**（光晕、投影、色块晕染），不要拿它画白字。
///
/// 保留原色的理由只有一条：压深后的填充色做投影只是一圈灰影，而原色
/// 在深色底上晕出来才看得见「这是哪一家」。
Color platformBrandHue(String platform) => switch (_id(platform)) {
  'tx' => const Color(0xFF31C27C),
  'kw' => const Color(0xFFFFC800),
  'wy' => const Color(0xFFE23B31),
  'kg' => const Color(0xFF00A0E9),
  _ => AppColors.textMuted,
};

/// 品牌填充色：白字压在上面的一整块底。
///
/// 每个值都是对应原色压深一档的结果，白字对比度见 [platformBrandFillContrast]。
/// 酷我那一档最尴尬——真正的黄压到白字可读已经接近"暗金"，所以胶囊外还
/// 留了一圈它原色的光晕，靠光而不是靠底色来认人。
Color platformBrandFill(String platform) => switch (_id(platform)) {
  'tx' => const Color(0xFF0D834E),
  'kw' => const Color(0xFF8F6B00),
  'wy' => const Color(0xFFC20C0C),
  'kg' => const Color(0xFF0C74AE),
  _ => const Color(0xFF3C4250),
};

/// 白字压在 [platformBrandFill] 上的 WCAG 对比度，用来钉住"不要看不清"。
///
/// 放在生产代码里而不是测试里，是因为改色的人打开文件就能看到这条底线，
/// 而不是等测试炸了才知道。
double platformBrandFillContrast(String platform) {
  final fill = platformBrandFill(platform);
  final fg = fill.computeLuminance();
  return (1.05) / (fg + 0.05);
}

/// `qq` 是 platformName 里的历史别名，没有任何 source 在用，但设置页导入
/// 时可能从旧存档里带出来，顺手认一下。
String _id(String platform) => platform == 'qq' ? 'tx' : platform;
