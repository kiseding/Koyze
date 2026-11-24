// 探针：确认「背后是纯色」的玻璃面在虚化档打开时**不会**多出采样层。
//
// 背景：虚化滑杆上线时（a996122）为了让所有玻璃面都吃这一档，把
// 「背后是纯色 → 跳过采样」的捷径改成只在虚化关闭时成立。结果是设置页
// 一屏四五张 700pt 高的整宽卡、榜单/歌单/搜索结果每行都变成真的采样，
// 而它们背后全是同一片纯色页面底——采样结果和直接混色逐像素相同。
//
// 修复引入 [GlassSurface.solidBehind]：调用方声明「我背后确定是纯色」，
// 这时无论虚化档多少都不采样。本文件钉住这条契约。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/theme/glass_config.dart';
import 'package:koyze/core/theme/effect_policy.dart';
import 'package:koyze/features/settings/presentation/settings_section_card.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: Column(children: [child])),
    ),
  );
}

Widget _card({required String title}) {
  return SettingsSectionCard(
    title: title,
    children: const [
      SizedBox(height: 56, child: Placeholder()),
      SizedBox(height: 56, child: Placeholder()),
      SizedBox(height: 56, child: Placeholder()),
      SizedBox(height: 56, child: Placeholder()),
    ],
  );
}

void main() {
  tearDown(() {
    GlassEffectConfig.setSurfaceBlur(GlassEffectConfig.defaultSurfaceBlur);
    GlassEffectConfig.setSurfaceOpacity(
      GlassEffectConfig.defaultSurfaceOpacity,
    );
  });

  group('solidBehind：背后确定是纯色时永不为采样付费', () {
    testWidgets('设置页卡片在虚化开到 100% 时也不建采样层', (tester) async {
      // 出厂档就是「虚化开」，所以这是用户默认会遇到的路径。
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              for (final title in ['播放', '音质', '歌词', '外观', '存储'])
                _card(title: title),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 五张卡，一张都不该采样。
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('设置页卡片在虚化关着时同样不采样', (tester) async {
      GlassEffectConfig.setSurfaceBlur(0);
      await tester.pumpWidget(_host(_card(title: '播放')));

      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('声明 solidBehind 的玻璃面在虚化开着时不采样', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(
        _host(
          const GlassSurface(
            style: AppGlassStyle.regular,
            solidBehind: true,
            child: SizedBox(height: 80),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('设置卡片滚动时不重建纯色材质面', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(
        _host(
          const GlassSurface(
            key: ValueKey('settings-surface'),
            style: AppGlassStyle.regular,
            backdrop: false,
            solidBehind: true,
            child: SizedBox(height: 80),
          ),
        ),
      );
      final before = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-surface')),
          matching: find.byType(DecoratedBox),
        ).first,
      );

      GlassScrollActivity.set(true);
      await tester.pump();
      GlassScrollActivity.set(false);
      await tester.pump();

      final after = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-surface')),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      expect(identical(after, before), isTrue);
    });

    testWidgets('可采样材质面仍响应滚动通知', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(
        _host(
          const GlassSurface(
            key: ValueKey('scrolling-glass'),
            style: AppGlassStyle.regular,
            child: SizedBox(height: 80),
          ),
        ),
      );
      final before = tester.widget<BackdropFilter>(
        find.descendant(
          of: find.byKey(const ValueKey('scrolling-glass')),
          matching: find.byType(BackdropFilter),
        ),
      );

      GlassScrollActivity.set(true);
      await tester.pump();

      final after = tester.widget<BackdropFilter>(
        find.descendant(
          of: find.byKey(const ValueKey('scrolling-glass')),
          matching: find.byType(BackdropFilter),
        ),
      );
      expect(identical(after, before), isFalse);
    });

    testWidgets('没声明 solidBehind 的面仍然响应虚化滑杆', (tester) async {
      // 这是上一条的反向守卫：不能为了省采样把「虚化」做成摆设。
      // 背后可能有滚动内容的面（首页搜索框的位置、歌单行等）必须照常采样。
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(
        _host(
          const GlassSurface(
            style: AppGlassStyle.regular,
            backdrop: false,
            child: SizedBox(height: 80),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('虚化档归零后，采样层会消失', (tester) async {
      GlassEffectConfig.setSurfaceBlur(1);
      await tester.pumpWidget(
        _host(
          const GlassSurface(
            style: AppGlassStyle.regular,
            child: SizedBox(height: 80),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);

      GlassEffectConfig.setSurfaceBlur(0);
      await tester.pump();

      expect(find.byType(BackdropFilter), findsNothing);
    });
  });
}
