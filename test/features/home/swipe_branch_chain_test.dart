import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/home/presentation/main_scaffold.dart';

/// 回归：连着滑不能"吞手"。
///
/// 之前位移记的是「当前页下标 + 像素 _dx」，页号要等补间落地、外层 goBranch
/// 之后才更新。补间还在跑时再来一下，方向仍然从旧页算，目标还是同一页——
/// 连着滑三下只前进一格，用起来就是"滑过去之后滑不动了"。
/// 现在位移是一根连续的滚动坐标，第二下从第一下落点接着算。
void main() {
  Widget app({
    required int currentIndex,
    required ValueChanged<int> onSelect,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: SwipeBranchContainer(
          currentIndex: currentIndex,
          onSelect: onSelect,
          children: const [
            ColoredBox(color: Colors.red),
            ColoredBox(color: Colors.green),
            ColoredBox(color: Colors.blue),
            ColoredBox(color: Colors.orange),
          ],
        ),
      ),
    );
  }

  testWidgets('补间还没跑完就再滑一下，会再前进一页', (tester) async {
    rootHeaderBranchIndex.value = 0;
    final selected = <int>[];
    await tester.pumpWidget(app(currentIndex: 0, onSelect: selected.add));
    await tester.pump();

    // 第一次：390 宽的 77%，松手判定去第 1 页。
    await tester.drag(
      find.byType(SwipeBranchContainer),
      const Offset(-300, 0),
    );
    // 只泵一帧：补间还在跑，路由也还没切（onSelect 尚未调用）。
    await tester.pump(const Duration(milliseconds: 16));
    expect(selected, isEmpty);

    // 第二下紧接着来：从当前位置继续，落点必须再往后一页，而不是回到第 1 页。
    await tester.drag(
      find.byType(SwipeBranchContainer),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(selected, [2]);
    expect(rootHeaderBranchIndex.value, 2);
  });

  testWidgets('补间中按住再原地松手，落到最近的那一页', (tester) async {
    rootHeaderBranchIndex.value = 0;
    final selected = <int>[];
    await tester.pumpWidget(app(currentIndex: 0, onSelect: selected.add));
    await tester.pump();

    await tester.drag(
      find.byType(SwipeBranchContainer),
      const Offset(-200, 0),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 按住接管（不动），再松手：补间停在半路，落点应该是离它最近的第 1 页。
    final gesture = await tester.startGesture(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, [1]);
  });
}
