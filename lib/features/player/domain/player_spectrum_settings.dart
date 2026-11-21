import 'package:flutter/foundation.dart';

/// 播放页实时频谱条的样式。
///
/// 放在 domain 而不是和绘制器一起：设置页要读它来做选择器，而设置层不应该
/// 依赖 player 的 presentation。绘制器那边 `switch` 这个枚举决定几何形状。
///
/// 五档是**五种不同的读法**，不是同一根柱子换圆角：
///
/// - [bars] 看「包络」：柱高即幅值，最直白。
/// - [leds] 看「档位」：一列离散方块，像老式电平表的灯柱。
/// - [dots] 看「轨迹」：每列一个浮动的光点，尾线连着底，幅度变化是位移。
/// - [ridges] 看「地形」：三层山脊叠在一起，前低后高，有纵深。
/// - [fade] 看「重心」：柱子向上化进背景，亮度压在底部。
enum SpectrumStyle {
  /// 竖柱 + 顶部峰值帽。最直白的「频谱分析仪」，与均衡器页的柱状语言一致。
  bars,

  /// 分段电平表：每列由若干方块组成，点亮的格数等于幅值。
  leds,

  /// 浮动光点：每列一个圆点，纵向位置跟着幅值走，底部拖一条细尾线。
  dots,

  /// 三层山脊：后层更高更暗，前层更矮更亮，叠出纵深。
  ridges,

  /// 消隐：柱子从底部的实色向上淡出到透明，地面压一条亮线。
  /// 最亮的地方在地板而不是顶端，观感是「光柱」而不是「柱子」。
  fade;

  /// 持久化用的稳定字符串。改枚举名不该让用户的设置失效，所以显式写死。
  String get storageValue => switch (this) {
    SpectrumStyle.bars => 'bars',
    SpectrumStyle.leds => 'leds',
    SpectrumStyle.dots => 'dots',
    SpectrumStyle.ridges => 'ridges',
    SpectrumStyle.fade => 'fade',
  };

  static SpectrumStyle fromStorage(
    Object? value, {
    SpectrumStyle fallback = SpectrumStyle.bars,
  }) {
    if (value is! String) return fallback;
    for (final style in SpectrumStyle.values) {
      if (style.storageValue == value) return style;
    }
    return fallback;
  }
}

/// 播放页频谱条的设置。
@immutable
class PlayerSpectrumSettings {
  const PlayerSpectrumSettings({
    this.enabled = true,
    this.style = SpectrumStyle.bars,
  });

  /// 是否显示。默认开——这是纯装饰，开着不会影响其它任何元素。
  final bool enabled;

  final SpectrumStyle style;

  PlayerSpectrumSettings copyWith({bool? enabled, SpectrumStyle? style}) =>
      PlayerSpectrumSettings(
        enabled: enabled ?? this.enabled,
        style: style ?? this.style,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'style': style.storageValue,
  };

  /// 解析持久化数据。字段缺失或类型不对时用默认值，不抛异常——
  /// 一份坏掉的设置不该让播放器起不来。
  factory PlayerSpectrumSettings.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'];
    return PlayerSpectrumSettings(
      enabled: enabled is bool ? enabled : true,
      style: SpectrumStyle.fromStorage(json['style']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerSpectrumSettings &&
      other.enabled == enabled &&
      other.style == style;

  @override
  int get hashCode => Object.hash(enabled, style);
}
