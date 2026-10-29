import '../../../core/theme/glass_config.dart';

/// 全屏播放页背景的两个可调档位：模糊强度与遮罩不透明度。
///
/// 这两个值原先写死在 [GlassEffectConfig] 里（模糊 60、遮罩 `0xCC`）。封面的
/// 明暗分布差别很大：深色封面叠上深色遮罩之后，歌词几乎读不出来；浅色封面
/// 配轻遮罩又会让白字糊成一片。一档参数没法同时照顾所有专辑，所以交给用户调。
///
/// 存的是「用户档位」而不是「生效值」：性能模式（简化动效 / 关闭玻璃效果）
/// 仍会在它之上叠加缩放。这样把模糊拉到 100 之后再打开简化动效，看到的依然
/// 是缩放后的结果，而不是「设置值突然被改写」。
abstract final class PlayerBackdrop {
  /// 与 [GlassEffectConfig] 原先写死的那一档一致，老用户升级后观感不变。
  static const double defaultBlur = 60;
  static const double minBlur = 0;
  static const double maxBlur = 100;

  /// 原先是 `0xCC`（204/255）黑或白遮罩。
  static const double defaultScrim = 0.8;
  static const double minScrim = 0;
  static const double maxScrim = 1;

  /// 越界、NaN、无穷都会落回默认值，避免一条坏记录把背景画成黑屏。
  static double clampBlur(double value) {
    if (!value.isFinite) return defaultBlur;
    return value.clamp(minBlur, maxBlur).toDouble();
  }

  static double clampScrim(double value) {
    if (!value.isFinite) return defaultScrim;
    return value.clamp(minScrim, maxScrim).toDouble();
  }

  /// 模糊档位的展示文案。sigma 没有单位，直接给整数。
  static String blurLabel(double value) => clampBlur(value).round().toString();

  /// 遮罩不透明度的展示文案，`0.8` → `80%`。
  static String scrimLabel(double value) =>
      '${(clampScrim(value) * 100).round()}%';

  /// 落到渲染前最后一刻的换算：用户档位 → 实际 sigma。
  static double effectiveBlur(double value) =>
      GlassEffectConfig.playerBackdropBlurFor(clampBlur(value));
}
