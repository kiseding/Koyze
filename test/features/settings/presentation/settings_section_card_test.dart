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
    expect(source, contains('BorderRadius.circular(18)'));
  });
}
