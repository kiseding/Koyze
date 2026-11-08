import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/glass_backdrop.dart';

/// 取出刚刚创建的那个 [RenderBackdropFilter]。
RenderBackdropFilter _render(WidgetTester tester) {
  return tester.renderObject<RenderBackdropFilter>(
    find.byType(BackdropFilter),
  );
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('GlassBackdrop 背景采样', () {
    testWidgets('没有分组时走独立采样', (tester) async {
      await tester.pumpWidget(
        _host(
          const GlassBackdrop(
            sigma: 12,
            child: SizedBox(width: 120, height: 48),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      // 独立采样不共享背景，引擎每块玻璃各抓一次。
      expect(_render(tester).backdropKey, isNull);
    });

    testWidgets('在 BackdropGroup 内共享同一份背景捕获', (tester) async {
      final groupKey = BackdropKey();
      await tester.pumpWidget(
        _host(
          BackdropGroup(
            backdropKey: groupKey,
            child: const GlassBackdrop(
              sigma: 12,
              child: SizedBox(width: 120, height: 48),
            ),
          ),
        ),
      );
      // 关键：这里必须是 group 的 key，而不是 null。为 null 表示分组没接上，
      // 一屏 N 块玻璃就还是 N 次全屏背景拷贝。
      expect(_render(tester).backdropKey, same(groupKey));
    });

    testWidgets('同组的多个玻璃共用一个 key', (tester) async {
      final groupKey = BackdropKey();
      await tester.pumpWidget(
        _host(
          BackdropGroup(
            backdropKey: groupKey,
            child: Column(
              children: const [
                GlassBackdrop(
                  sigma: 8,
                  child: SizedBox(width: 120, height: 48),
                ),
                GlassBackdrop(
                  sigma: 16,
                  child: SizedBox(width: 120, height: 48),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      final keys = find
          .byType(BackdropFilter)
          .evaluate()
          .map((element) => (element.renderObject! as RenderBackdropFilter).backdropKey)
          .toList();
      expect(keys, everyElement(same(groupKey)));
    });

    testWidgets('sigma 为 0 不建图层', (tester) async {
      await tester.pumpWidget(
        _host(
          const GlassBackdrop(
            sigma: 0,
            child: SizedBox(width: 120, height: 48),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('走 filterConfig 而不是已废弃的 filter', (tester) async {
      await tester.pumpWidget(
        _host(
          const GlassBackdrop(
            sigma: 10,
            child: SizedBox(width: 120, height: 48),
          ),
        ),
      );
      final widget = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      // filter 已被 Flutter 标记废弃，且该 getter 在只设 filterConfig 时会
      // 断言失败，所以这里只确认新路径被用上。
      expect(widget.filterConfig, isNotNull);
    });
  });
}
