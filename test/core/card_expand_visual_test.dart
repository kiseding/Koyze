import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/card_expand.dart';

/// 卡片展开 / 收拢的**画面正确性**契约。
///
/// 已有的 card_expand_frames_test 只钉住「窗口宽度有中间态」，
/// card_expand_morph_test 只钉住 opaque / barrier / 时长。两者合起来
/// 仍然漏掉了现场的三个真实症状：
///
/// 1. 打开时首页元素一直盖在详情页上（搜索框、功能卡片、迷你条），
///    因为透明路由不裁剪下层，而转场层只在窗口内部铺底色——窗口之外
///    全透明。录屏 f684~f696 里搜索区与首页像素差只有 0.6。
/// 2. 收拢时窗口把顶栏先裁掉（`Alignment.center`），页面看起来散架。
/// 3. 收尾几帧窗口先收缩（203→163）又反向涨回 201，然后冻结 7 帧，
///    最后硬切——用户说的"收尾闪烁"。
///
/// 本文件分别钉住这三条。
void main() {
  /// 转场窗口：`Positioned.fromRect` 里那块圆角 18 的 ClipRRect。
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

  Future<void> pushExpandable(
    WidgetTester tester, {
    required ValueKey<String> pageKey,
    Rect? sourceRect,
    Widget body = const ColoredBox(color: Color(0xFF2B7A3D)),
  }) async {
    final page = expandablePage(pageKey, body, expandRect: sourceRect);
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
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  testWidgets('展开时窗口之外必须有不透明底色，不能露出下层页面', (tester) async {
    debugResetCardExpandOrigins();
    await pushExpandable(
      tester,
      pageKey: const ValueKey('backdrop-probe'),
      sourceRect: const Rect.fromLTWH(16, 300, 380, 150),
    );

    // 取动画中段（约 40%）：这时窗口还远没长满，窗口外一定要有东西挡着。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final windows = transitionWindows();
    expect(windows, isNotEmpty, reason: '中段应该有转场窗口');
    final window = windows.first;

    // 找一个明确在窗口之外、又在屏幕之内的点。
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(
      window.bottom,
      lessThan(screenHeight - 8),
      reason: '中段窗口应该还没长到屏幕底部，否则这条断言测不到东西',
    );

    // 判定「窗口之外有没有东西挡着」。
    //
    // 必须在**转场层内部**找，不能扫整棵树：测试脚手架的 Scaffold
    // 自己就有一层 800x600@0,0 的背景，扫全树会把它当成兜底底色。
    //
    // 转场层里可能出现尺寸等于整屏的 ColoredBox 有两种来路：
    //   · 兜底底色 —— 铺在窗口之下，起点在整屏原点
    //   · 窗口内部那层背景被 OverflowBox/Transform 放大回整屏
    //     —— 尺寸也是整屏，但**位置跟着窗口走**（旧实现实测 @4.7,68.9）
    // 所以既要限定在转场层内，又要同时要求起点在原点。
    final expandLayer = find.ancestor(
      of: find.byWidgetPredicate(
        (w) => w is ClipRRect && w.borderRadius == BorderRadius.circular(18),
      ),
      matching: find.byType(Stack),
    );
    final scopedBoxes = <Element>{
      for (final stack in expandLayer.evaluate())
        ...find
            .descendant(
              of: find.byWidget(stack.widget),
              matching: find.byType(ColoredBox),
            )
            .evaluate(),
    };
    final fullScreenBackdrops = <Rect>[];
    for (final element in scopedBoxes) {
      final box = element.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final size = box.size;
      if (size.width < screenWidth - 1) continue;
      if (size.height < screenHeight - 1) continue;
      final origin = box.localToGlobal(Offset.zero);
      // 兜底底色固定在整屏原点；窗口内部的放大会带偏移。
      if (origin.dx.abs() > 1 || origin.dy.abs() > 1) continue;
      fullScreenBackdrops.add(origin & size);
    }
    expect(
      fullScreenBackdrops,
      isNotEmpty,
      reason:
          '中段（窗口 ${window.width.toStringAsFixed(0)}x'
          '${window.height.toStringAsFixed(0)}，还没长满整屏 '
          '${screenWidth.toStringAsFixed(0)}x${screenHeight.toStringAsFixed(0)}）'
          '时，转场层里没有任何**铺满整屏且贴着原点**的底色：'
          '窗口之外直接透明，首页会一直盖在详情页上'
          '（现场症状：搜索框/功能卡片/迷你条在详情页铺满后仍然可见，'
          '录屏 f684~f696 里搜索区与首页的像素差只有 0.6）。',
    );
  });

  testWidgets('收拢时内容顶对齐，窗口变矮不会把顶栏裁掉', (tester) async {
    debugResetCardExpandOrigins();
    await pushExpandable(
      tester,
      pageKey: const ValueKey('align-probe'),
      sourceRect: const Rect.fromLTWH(16, 300, 380, 150),
      body: const _TopMarkedBody(),
    );

    // 跑到接近全屏，再让窗口收缩一小段（不 pop，只读几何）。
    for (var i = 0; i < 19; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 内容层是被 Transform.scale 包住的整屏 SizedBox。它的对齐方式决定了
    // 窗口变矮时裁掉哪一头。
    var topAlignedContent = 0;
    var centerAlignedContent = 0;
    for (final element in find.byType(OverflowBox).evaluate()) {
      final box = element.widget as OverflowBox;
      final maxHeight = box.maxHeight;
      if (maxHeight == null || maxHeight < 300) continue;
      if (box.alignment == Alignment.topCenter) {
        topAlignedContent++;
      } else if (box.alignment == Alignment.center) {
        centerAlignedContent++;
      }
    }
    expect(
      topAlignedContent,
      greaterThan(0),
      reason:
          '目的页应顶对齐（topCenter）。用 center 时窗口一矮就先把'
          '标题栏和返回键裁掉，收拢过程看起来像页面散架'
          '（center 对齐的发现 ${centerAlignedContent} 处）',
    );
  });

  testWidgets('收拢全程窗口宽度单调收缩，不反向增长', (tester) async {
    debugResetCardExpandOrigins();
    await pushExpandable(
      tester,
      pageKey: const ValueKey('monotonic-probe'),
      sourceRect: const Rect.fromLTWH(16, 300, 380, 150),
    );

    // 先跑完展开
    for (var i = 0; i < 22; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final expandedWidth = transitionWindows().isEmpty
        ? null
        : transitionWindows().first.width;
    expect(expandedWidth, isNotNull);
    // 源卡片 380 宽，屏幕 800 宽：展开后窗口应该已经接近整屏。
    expect(expandedWidth!, greaterThan(700));

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    navigator.pop();
    await tester.pump();

    final widths = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final windows = transitionWindows();
      if (windows.isEmpty) break;
      widths.add(windows.first.width);
    }

    expect(
      widths.length,
      greaterThanOrEqualTo(6),
      reason: '收拢应该有中间态，实际只采到 ${widths.length} 帧',
    );

    // 允许极小抖动（亚像素），但绝不允许"先缩小又长大"这种反向。
    //
    // 反向增长意味着两个进度源在打架（路由动画 vs 手势 dismiss 进度），
    // 画面会先缩再涨，然后突然收束——现场录屏里窗口宽度
    // 203→163（收缩）→201（回涨）→冻结 7 帧→归零 就是这个形态。
    var regressions = 0;
    var worst = 0.0;
    for (var i = 1; i < widths.length; i++) {
      final delta = widths[i] - widths[i - 1];
      if (delta > 2.0) {
        regressions++;
        if (delta > worst) worst = delta;
      }
    }
    expect(
      regressions,
      0,
      reason:
          '收拢过程出现 $regressions 次反向增长（最大 +${worst.toStringAsFixed(1)}px）。'
          '宽度序列：${widths.map((w) => w.toStringAsFixed(0)).join(" → ")}',
    );
  });

  testWidgets('收拢节奏均匀：末段每帧仍可见位移，不会越走越慢直到静止', (tester) async {
    debugResetCardExpandOrigins();
    const sourceRect = Rect.fromLTWH(16, 300, 380, 150);
    await pushExpandable(
      tester,
      pageKey: const ValueKey('rhythm-probe'),
      sourceRect: sourceRect,
    );

    for (var i = 0; i < 22; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    navigator.pop();
    await tester.pump();

    final widths = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final windows = transitionWindows();
      if (windows.isEmpty) break;
      widths.add(windows.first.width);
    }
    expect(
      widths.length,
      greaterThanOrEqualTo(6),
      reason: '收拢应该有足够多的采样帧，实际 ${widths.length} 帧',
    );

    // 逐帧位移量。这就是"收尾闪烁"的可测量本质：
    //
    // 旧实现的反向曲线是 easeInCubic，`t = 1 - animation.value` 把它翻过来
    // 之后，逐帧位移是 -90, -84, -70, -55, -41, -28, -19, -13, -9, -6——
    // 越走越慢，最后几帧几乎不动。用户先感到"动画已经结束了"，随后路由
    // pop 完成、画面硬切回首页，那一下就是闪烁。
    //
    // 线性反向之后逐帧位移是恒定的（实测 -37 × 11 帧），全程都有变化。
    final deltas = <double>[];
    for (var i = 1; i < widths.length; i++) {
      deltas.add(widths[i] - widths[i - 1]);
    }

    // 每个位移都必须是负的（纯收缩）
    expect(
      deltas.every((d) => d <= 0.5),
      isTrue,
      reason:
          '收拢过程出现反向增长：'
          '${deltas.map((d) => d.toStringAsFixed(0)).join(", ")}',
    );

    // 末帧位移不能塌到接近 0——那意味着最后一段时间画面是静止的。
    //
    // 用「末三段平均位移 / 中段位移」衡量节奏。线性反向下两条曲线相同，
    // 比值应该接近 1；easeInCubic 反向是 -84,-70,-55,-41,-28,-19,-13,-9,-6，
    // 末段只剩中段的 1/3，画面越走越慢直到停住。
    //
    // 阈值 0.7 就是这么定的：新实现实测 ≈1.0，旧实现实测 0.329，
    // 两边都留了余量，不会因为帧率抖动误报。
    final n = deltas.length;
    final mid = deltas[n ~/ 2].abs();
    final tail =
        deltas.sublist(n - 3).map((d) => d.abs()).reduce((a, b) => a + b) / 3;
    expect(
      tail,
      greaterThan(mid * 0.7),
      reason:
          '收拢末段明显减速（中段每帧 ${mid.toStringAsFixed(1)}px，'
          '末段每帧 ${tail.toStringAsFixed(1)}px，比值 '
          '${(tail / mid).toStringAsFixed(2)}）。'
          '位移越走越小、末尾趋近于零 = 动画提前"结束"，之后才硬切——'
          '这就是收尾闪烁。逐帧位移：'
          '${deltas.map((d) => d.toStringAsFixed(0)).join(", ")}',
    );
  });
}

/// 顶部有一块明显标记的内容，用来观察顶栏有没有被裁掉。
class _TopMarkedBody extends StatelessWidget {
  const _TopMarkedBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(height: 56, color: const Color(0xFFFF00FF)),
        const Expanded(child: ColoredBox(color: Color(0xFF101820))),
      ],
    );
  }
}
