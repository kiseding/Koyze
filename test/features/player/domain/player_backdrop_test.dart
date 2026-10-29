import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/features/player/domain/player_backdrop.dart';

void main() {
  tearDown(() {
    GlassEffectConfig.applyPerformanceMode(reduceEffects: false);
    GlassEffectConfig.setDisableAllGlassEffects(false);
  });

  test('out-of-range blur lands inside the slider range', () {
    expect(PlayerBackdrop.clampBlur(-40), PlayerBackdrop.minBlur);
    expect(PlayerBackdrop.clampBlur(240), PlayerBackdrop.maxBlur);
    expect(PlayerBackdrop.clampBlur(42), 42);
  });

  test('a corrupt record cannot paint a blank background', () {
    // 磁盘里可能是 NaN（旧版本写过 0/0）或 Infinity，直接传给 ImageFilter
    // 会让整块背景消失，用户看到的是纯色页面而不是「模糊了很多」。
    expect(PlayerBackdrop.clampBlur(double.nan), PlayerBackdrop.defaultBlur);
    expect(
      PlayerBackdrop.clampBlur(double.infinity),
      PlayerBackdrop.defaultBlur,
    );
    expect(PlayerBackdrop.clampScrim(double.nan), PlayerBackdrop.defaultScrim);
    expect(
      PlayerBackdrop.clampScrim(double.negativeInfinity),
      PlayerBackdrop.defaultScrim,
    );
  });

  test('scrim stays a legal alpha', () {
    expect(PlayerBackdrop.clampScrim(-0.5), PlayerBackdrop.minScrim);
    expect(PlayerBackdrop.clampScrim(2), PlayerBackdrop.maxScrim);
  });

  test('labels round instead of showing float noise', () {
    expect(PlayerBackdrop.blurLabel(60.4), '60');
    expect(PlayerBackdrop.blurLabel(0), '0');
    expect(PlayerBackdrop.scrimLabel(0.8), '80%');
    expect(PlayerBackdrop.scrimLabel(0.456), '46%');
    expect(PlayerBackdrop.scrimLabel(0), '0%');
  });

  test('the stored tier still gets scaled by performance mode', () {
    // 存的是「用户档位」，不是生效值：同一个 60 在简化动效下应该更轻，
    // 否则打开简化动效时背景会毫无变化，用户以为开关坏了。
    final normal = PlayerBackdrop.effectiveBlur(PlayerBackdrop.defaultBlur);
    GlassEffectConfig.applyPerformanceMode(reduceEffects: true);
    final reduced = PlayerBackdrop.effectiveBlur(PlayerBackdrop.defaultBlur);

    expect(normal, greaterThan(40));
    expect(reduced, lessThan(normal));

    GlassEffectConfig.setDisableAllGlassEffects(true);
    expect(PlayerBackdrop.effectiveBlur(PlayerBackdrop.defaultBlur), 0);
  });

  test('zero blur is honoured rather than treated as "unset"', () {
    expect(PlayerBackdrop.effectiveBlur(0), 0);
  });

  test('the default tier stays pinned to the shipped backdrop level', () {
    // 默认档位与 GlassEffectConfig 里那一档是同一个数，分居两个文件。
    // 谁改了其中一个而忘了另一个，这条会立刻红——否则只有用户会发现
    // 「升级之后背景突然变糊/变清」。
    expect(
      PlayerBackdrop.effectiveBlur(PlayerBackdrop.defaultBlur),
      GlassEffectConfig.playerBackdropBlur,
    );
  });
}
