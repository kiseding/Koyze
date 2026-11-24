import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/player/presentation/widgets/spectrum_style_sheet.dart';
import 'package:koyze/features/settings/presentation/settings_notifiers.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 样式面板的两个约定：光点排第一（也就是默认值），以及右上角有关闭键。
///
/// 面板挂在设置页「播放」区的一行上，这里用一个按钮把它打开，避免把整页
/// 设置和播放引擎都拖进测试。
void main() {
  Future<void> openSheet(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final container = ProviderContainer(
      overrides: [
        // `StorageService.instance` 是进程级单例，钉在这份内存存储上，
        // 免得跨用例读到上一份快照。
        playerSpectrumProvider.overrideWith(
          () => PlayerSpectrumNotifier(storage: () async => storage),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: TextButton(
                  onPressed: () => showSpectrumStyleSheet(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    // 面板里每一行都挂着循环播放的预览动画，pumpAndSettle 永远等不到静止。
    // 固定推两帧：一帧建出弹层路由，一帧走完入场动画。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('光点排在第一位，并且是默认选中项', (tester) async {
    await openSheet(tester);

    expect(find.text('Spectrum style'), findsOneWidget);
    // 面板按 SpectrumStyle.values 渲染，第一项就是默认值；两项必须同时
    // 改，否则默认选中项会落在列表中间，看起来像没选中任何样式。
    final dotsY = tester.getTopLeft(find.text('Glow dots')).dy;
    final barsY = tester.getTopLeft(find.text('Bars')).dy;
    expect(dotsY, lessThan(barsY), reason: '光点应该排在柱状前面');

    final dotsRow = find
        .ancestor(
          of: find.text('Glow dots'),
          matching: find.byType(AnimatedContainer),
        )
        .first;
    expect(
      find.descendant(of: dotsRow, matching: find.byIcon(Icons.check)),
      findsOneWidget,
      reason: '空存储下默认样式是光点，勾应该在这一行',
    );
  });

  testWidgets('右上角关闭键能关掉面板', (tester) async {
    await openSheet(tester);

    // 这一层只有选项和离开两种动作，没有确定键；缺了关闭键就只能下滑或
    // 点遮罩，和设置页其它选择弹窗不一致。
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Spectrum style'), findsNothing);
  });
}
