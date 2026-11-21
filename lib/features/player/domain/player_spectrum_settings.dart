import 'package:flutter/foundation.dart';

/// 播放页实时频谱条的样式。
///
/// 放在 domain 而不是和绘制器一起：设置页要读它来做选择器，而设置层不应该
/// 依赖 player 的 presentation。绘制器那边 `switch` 这个枚举决定几何形状。
enum SpectrumStyle {
  /// 竖柱 + 顶部峰值帽。最直白的「频谱分析仪」，与均衡器页的柱状语言一致。
  bars,

  /// 圆头细柱，柱宽与间距接近 1:1，比 [bars] 轻。窄条上更干净。
  pills,

  /// 镜像柱：以条的水平中线为轴上下对称。视觉重心居中，不压迫下方进度条。
  mirror,

  /// 平滑曲线 + 向下渐隐的面积填充。没有柱子边界，适合「氛围」而非「仪表」。
  wave,

  /// 曲线 + 上下对称填充，像声波包络。比 [wave] 更有体积感。
  ribbon;

  /// 持久化用的稳定字符串。改枚举名不该让用户的设置失效，所以显式写死。
  String get storageValue => switch (this) {
    SpectrumStyle.bars => 'bars',
    SpectrumStyle.pills => 'pills',
    SpectrumStyle.mirror => 'mirror',
    SpectrumStyle.wave => 'wave',
    SpectrumStyle.ribbon => 'ribbon',
  };

  static SpectrumStyle fromStorage(Object? value, {SpectrumStyle fallback = SpectrumStyle.bars}) {
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