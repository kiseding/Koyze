import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 开关的视觉缩放系数。
///
/// Flutter 的 `Switch` 布局盒固定是 60×40（轨道本体 52×32，四周各留 4 的
/// 投影余量），`SwitchThemeData` 只能改配色、`padding` 只能改宽度，没有
/// 任何公开钩子能改尺寸。项目里所有开关都比旁边 13.5~14 号字、40 高的行
/// 显得敦实，所以统一缩到 0.88：轨道 52→45.8 宽、32→28.2 高，视觉上与
/// 周围的字重、图标（20~22）终于一个量级。
///
/// 只缩视觉，不动 hit test：开关本体在缩放前仍是 60×40，`Transform.scale`
/// 只改绘制矩阵、不改命中区域，所以点按范围反而比看起来更大——这对触屏
/// 是好事，不该"顺手"缩掉。
const double kSwitchVisualScale = 0.88;

/// `Switch` 未经缩放的布局尺寸，用于反算缩放后应占的位置。
const Size kSwitchIntrinsicSize = Size(60, 40);

/// 开关。
///
/// 外观与「翻译行」（`SwitchListTile.adaptive`）里那颗一致：iOS / macOS 走
/// Cupertino 样式，其余平台走 Material，配色、按压与拖拽手感、无障碍语义
/// 全部交给平台控件。唯一的偏差是整体按 [kSwitchVisualScale] 缩小，见上。
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
    this.height = 48,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 开关占位的高度。
  ///
  /// 默认 48：大多数页面里这一行没有别的东西撑着，留 48 行才不会比旁边
  /// 的行矮。设置页现在所有行都有统一的最小高度（`kSettingsRowMinHeight`），
  /// 那里传 40 就够放下缩到 0.88 的开关本体，行高交给下限去保证。
  final double height;

  /// 打开时的强调色；null = 主题 primary。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: buildScaledSwitch(
          value: value,
          onChanged: onChanged,
          // 显式取主题 primary，和改造前那颗行为完全一致。
          accent: accent ?? AppColors.accentOf(context),
        ),
      ),
    );
  }
}

/// 构造一颗按 [kSwitchVisualScale] 缩放好的平台开关，供 [FxSwitch] 与
/// [FxSwitchTile] 共用。
///
/// 单独抽出来是因为 `SwitchListTile.adaptive` 没法只换内部那颗开关——它的
/// 开关是写死构建的。想同时保住「整行可点 + 系统语义」和「尺寸统一」，就
/// 只能自己拼一个 ListTile，把缩好的开关当 `trailing` 塞进去。
Widget buildScaledSwitch({
  required bool value,
  required ValueChanged<bool>? onChanged,
  Color? accent,
}) {
  return Transform.scale(
    scale: kSwitchVisualScale,
    child: Switch.adaptive(
      value: value,
      onChanged: onChanged,
      // 和 SwitchListTile.adaptive 一样：不等比放大 tap 目标，
      // 免得这一行比别的行高出一截。
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      activeThumbColor: accent,
    ),
  );
}

/// 带开关的一行，等价于 `SwitchListTile.adaptive`，但开关是缩小过的。
///
/// 行为逐条对齐被替换掉的那个系统控件：
///
/// - 整行可点（`onTap` 翻转 `!value`），不只是右边那颗开关；
/// - 开关套 `IgnorePointer`，手势全部交给外层这一层，否则点开关会连着
///   触发两次（先开关、再整行），切回去等于没变；
/// - `MergeSemantics` 把标题、副标题、开关的语义并成一条，读屏念一次；
/// - `enabled: onChanged != null`，禁用时整行都不响应。
///
/// 两个容易踩的细节：
///
/// 1. `ListTile` 的 `onTap` 会给语义节点打上 `isButton`，读屏会念成「按钮」
///    而不是「开关，已打开」。`SwitchListTile` 靠
///    `internalAddSemanticForOnTap: false` 关掉它，这里必须照抄——否则同一
///    个设置页里，换过的行念法会和没换的行不一样。
/// 2. 既然关掉了那一层语义，点击就得自己用 `InkWell` 包，水波纹和焦点框
///    才还在（`ListTile` 内部那个 `InkWell` 拿不到 `onTap` 就不出效果）。
///
/// 之所以不直接包一层 `Transform.scale` 套住整个 `SwitchListTile`：那样会
/// 连标题字号、行高、左右内边距一起缩小，而这些本来就该是正常大小——只有
/// 开关偏大。
class FxSwitchTile extends StatelessWidget {
  const FxSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.accent,
    this.dense = false,
    this.contentPadding,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget? subtitle;

  /// 打开时的强调色；null = 主题 primary。
  final Color? accent;

  /// 紧凑排版。开关缩过之后行本身通常也能跟着收紧，但这里不替调用方
  /// 决定——`SwitchListTile` 的 `dense` 本来就只影响字号和间距。
  final bool dense;

  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    void toggle() => onChanged!(!value);

    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? toggle : null,
        child: ListTile(
          title: title,
          subtitle: subtitle,
          trailing: IgnorePointer(
            child: ExcludeFocus(
              child: buildScaledSwitch(
                value: value,
                onChanged: onChanged,
                accent: accent,
              ),
            ),
          ),
          dense: dense,
          contentPadding: contentPadding,
          enabled: enabled,
          // 语义由外层 InkWell + 开关自己承担，别在这里再标一次「按钮」。
          internalAddSemanticForOnTap: false,
        ),
      ),
    );
  }
}
