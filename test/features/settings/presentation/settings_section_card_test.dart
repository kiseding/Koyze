import 'package:flutter_test/flutter_test.dart';

import '../../../support/source_text.dart';

/// 设置页分区卡片的材质护栏。
///
/// 榜单的行内播放键踩过同一个坑（见 leaderboard_play_feedback_test）：
/// 一块玻璃面单独看很便宜，铺满一屏滚动列表就变成每帧好几次全宽模糊。
void main() {
  final source = readSource(
    'lib/features/settings/presentation/settings_section_card.dart',
  );

  test('分区卡片不挂 BackdropFilter', () {
    // 卡片背后是纯色页面底，模糊采到的就是同一个颜色；关掉采样直接混出
    // 实色，画面一模一样，却省掉一屏四五层实时模糊。
    expect(source, contains('GlassSurface('));
    expect(source, contains('backdrop: false'));
  });

  test('卡片仍是同一块玻璃材质，圆角与边线都从 AppGlass 取', () {
    expect(source, contains('style: AppGlassStyle.regular'));
    expect(source, contains('AppGlass.hairline('));
    // 圆角必须走共享常量：卡片不裁剪内容，行内水波纹要按同一半径自己收边
    // （见 settings_screen 里的 customBorder），两处不能各写一个数字。
    expect(source, contains('borderRadius: kSettingsCardRadius'));
    expect(
      source,
      contains(
        'const BorderRadius kSettingsCardRadius = '
        'BorderRadius.all(Radius.circular(18))',
      ),
    );
  });

  test('卡片不裁剪内容：整卡抗锯齿裁剪是滑动掉帧的主因', () {
    // ClipRRect 走抗锯齿裁剪时，渲染器要为整块面积生成覆盖率遮罩，且这块
    // 工作落在每帧重画的那一边（滚动缓存覆盖不到）。设置页一屏三四张
    // 700pt 高的卡片，逐帧重做遮罩就是肉眼可见的掉帧。
    expect(source, contains('clipContent: false'));
  });
}
