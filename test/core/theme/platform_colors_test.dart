import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/platform_colors.dart';

/// 榜单页平台胶囊把白字压在品牌色上，四家的原色对比度差得很远：
/// QQ 绿、酷我黄直接铺白字是看不清的。这里钉住"改色不能把字弄丢"。
void main() {
  const platforms = ['tx', 'kw', 'wy', 'kg'];

  test('四家平台的填充色都让白字达到 AA（≥ 4.5:1）', () {
    for (final platform in platforms) {
      final ratio = platformBrandFillContrast(platform);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$platform 的白字对比度只有 ${ratio.toStringAsFixed(2)}:1',
      );
    }
  });

  test('填充色互不相同：四颗胶囊不能长成同一块', () {
    final fills = {for (final p in platforms) platformBrandFill(p).toARGB32()};
    expect(fills.length, platforms.length);
  });

  test('未知平台退回深中性灰，不借别的平台的颜色', () {
    final fallback = platformBrandFill('other');
    expect(fallback, isNot(platformBrandFill('tx')));
    expect(fallback.computeLuminance(), lessThan(0.2));
  });

  test('历史别名 qq 和 tx 是同一家', () {
    expect(platformBrandFill('qq'), platformBrandFill('tx'));
  });

  testWidgets('墨色：浅色主题就是填充色，深色主题一定更亮', (tester) async {
    Future<Map<String, Color>> ctxFor(Brightness brightness) async {
      late Map<String, Color> resolved;
      await tester.pumpWidget(
        MaterialApp(
          // brightness 单独传不生效：ThemeData.brightness 是从 colorScheme
          // 反推的，colorScheme 默认是亮色，两种主题会读到同一个值。
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF31C27C),
              brightness: brightness,
            ),
          ),
          // 色值必须在这次 build 里就地取走。BuildContext 是个活的 element
          // 引用，等下一轮换了主题再回头读，拿到的会是新主题的颜色。
          home: Builder(
            builder: (context) {
              resolved = {
                for (final platform in platforms)
                  platform: platformBrandColor(context, platform),
              };
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // MaterialApp 换主题走的是 AnimatedTheme，200ms 过渡结束前读到的
      // 还是上一个亮度。
      await tester.pumpAndSettle();
      return resolved;
    }

    final light = await ctxFor(Brightness.light);
    final dark = await ctxFor(Brightness.dark);

    for (final platform in platforms) {
      expect(
        light[platform],
        platformBrandFill(platform),
        reason: '$platform 在浅色主题下不该再提亮',
      );
      expect(
        dark[platform]!.computeLuminance(),
        greaterThan(platformBrandFill(platform).computeLuminance()),
        reason: '$platform 在深色主题下没有提亮，深底上会糊成一团',
      );
    }
  });

  testWidgets('原色只做光晕，不承担文字对比', (tester) async {
    // 原色比填充色亮是设计意图（光晕要跳出来），这条断言的作用是防止有人
    // 把原色又当成胶囊底色用回去。
    for (final platform in platforms) {
      expect(
        platformBrandHue(platform).computeLuminance(),
        greaterThan(platformBrandFill(platform).computeLuminance()),
        reason: '$platform 的原色不该比填充色更暗',
      );
    }
  });
}
