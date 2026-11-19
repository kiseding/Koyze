import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/card_expand.dart';

/// 卡片展开必须有逐帧中间态，不能一帧跳到底。
///
/// 现场表现：点收藏列表卡片，卡片没长过，直接整屏换成列表页；退出倒是
/// 有完整收拢动画。录屏逐帧比对显示展开侧「首页 → 列表」只隔 1 帧
/// （11.359s → 11.376s），而配置的时长是 300ms——按 60fps 应该有 18 帧
/// 中间态。这个文件就是钉住「中间态确实存在」。
///
/// 已有的 card_expand_morph_test 只断言 opaque / barrier / 时长非零，
/// 全程没有检查过任何一帧的实际几何，所以 morph 丢光了它也不会红。
void main() {
  /// 转场窗口是 `Positioned.fromRect` 里那块圆角 18 的 ClipRRect。
  /// 用同一个圆角去定位它，读它的当前尺寸。
  List<Rect> transitionWindows() {
    final rects = <Rect>[];
    for (final element in find.byType(ClipRRect).evaluate()) {
      final widget = element.widget as ClipRRect;
      if (widget.borderRadius != BorderRadius.circular(18)) continue;
      final box = element.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      rects.add(box.localToGlobal(Offset.zero) & box.size);
    }
    return rects;
  }

  testWidgets('展开过程中出现多个不同宽度，不是一帧跳到底', (tester) async {
    debugResetCardExpandOrigins();

    const sourceRect = Rect.fromLTWH(16, 300, 380, 150);
    final page = expandablePage(
      const ValueKey('expand-probe'),
      const ColoredBox(color: Color(0xFF2B7A3D)),
      expandRect: sourceRect,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).push(page.createRoute(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    await tester.tap(find.text('open'));
    await tester.pump();

    final widths = <double>[];
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final windows = transitionWindows();
      if (windows.isEmpty) continue;
      final w = windows.first.width;
      if (widths.isEmpty || (w - widths.last).abs() > 0.5) widths.add(w);
    }

    expect(
      widths.length,
      greaterThanOrEqualTo(8),
      reason:
          '展开采样到 ${widths.length} 个不同宽度（${widths.map((w) => w.toStringAsFixed(0)).join(", ")}），'
          '应该接近 18 个（300ms / 16ms）。只有 1~2 个说明动画没播，'
          '直接跳到全屏宽度 ${screenWidth.toStringAsFixed(0)}。',
    );
    expect(
      widths.first,
      lessThan(screenWidth - 40),
      reason: '起始帧应该还接近卡片宽度，实际是 ${widths.first}',
    );
    expect(
      widths.last,
      greaterThan(screenWidth * 0.9),
      reason: '结束帧应该接近全屏宽度，实际是 ${widths.last}',
    );
  });
}