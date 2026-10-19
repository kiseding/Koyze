import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/glass_config.dart';

void main() {
  tearDown(() {
    GlassEffectConfig.applyPerformanceMode(reduceEffects: false);
    GlassEffectConfig.setDisableAllGlassEffects(false);
  });

  test('the now-playing backdrop blurs much harder than any panel', () {
    // 播放页是整屏糊，面板是局部糊。两者共用一档时背景会「只是有点虚」，
    // 封面的字还认得出来——这正是这一档存在的原因。
    expect(
      GlassEffectConfig.playerBackdropBlur,
      greaterThan(GlassEffectConfig.modalBlur * 1.5),
    );
    expect(GlassEffectConfig.playerBackdropBlur, greaterThan(40));
  });

  test('performance mode scales the backdrop down but keeps it soft', () {
    GlassEffectConfig.applyPerformanceMode(reduceEffects: true);
    expect(GlassEffectConfig.playerBackdropBlur, lessThan(52));
    expect(GlassEffectConfig.playerBackdropBlur, greaterThan(30));
  });

  test('disabling glass effects turns the backdrop filter off', () {
    GlassEffectConfig.setDisableAllGlassEffects(true);
    expect(GlassEffectConfig.playerBackdropBlur, 0);
  });
}
