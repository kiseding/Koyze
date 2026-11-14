import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 开关。
///
/// 外观与「翻译行」（`SwitchListTile.adaptive`）里那颗完全一致：iOS / macOS
/// 走 Cupertino 样式，其余平台走 Material，尺寸、thumb 与轨道的配色、按压
/// 与拖拽手感、无障碍语义全部交给平台控件。
///
/// 以前这里是自己画的 44×26 胶囊：和系统开关并排时大小、thumb 颜色、按压
/// 反馈都不一样，同一个设置页里看着像两套设计。自绘还额外背了一套键盘焦点
/// 和语义实现，收益却只有「能自定义轨道颜色」这一条。
///
/// [accent] 是打开时的强调色，默认取主题 primary——和「翻译行」那颗一致。
/// 少数按平台品牌色区分的开关（榜单里的各平台可见性）才显式传。
class FxSwitch extends StatelessWidget {
  const FxSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.accent,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 打开时的强调色；null = 主题 primary。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 行高按 48 留：开关本体只有 32 高，直接放进 Row 会把整行高度带下来。
      height: 48,
      child: Center(
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          // 和 SwitchListTile.adaptive 一样：不等比放大 tap 目标，
          // 免得这一行比别的行高出一截。
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          activeThumbColor: accent ?? AppColors.accentOf(context),
        ),
      ),
    );
  }
}
