import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/widgets/koyze_modal.dart';
import 'package:koyze/core/widgets/koyze_sheet.dart';

/// 弹层不应该贴边：贴边的面板看起来像一次页面跳转，而不是浮在当前页上。
/// 这里直接量面板的屏幕矩形，避免以后有人调 constraints 时又把它铺满。
Future<Rect> _openSheetAndMeasure(
  WidgetTester tester,
  Size size, {
  bool frosted = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            showKoyzeSheet<void>(
              context: context,
              backgroundColor: frosted ? null : Colors.transparent,
              builder: (_) =>
                  const SizedBox(key: ValueKey('sheet-body'), height: 200),
            );
          },
          child: const Text('open-sheet'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open-sheet'));
  await tester.pumpAndSettle();
  return tester.getRect(find.byKey(const ValueKey('sheet-body')));
}

void main() {
  testWidgets('sheet max height stays below the status bar', (tester) async {
    late double height;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          padding: EdgeInsets.only(top: 59, bottom: 34),
          viewPadding: EdgeInsets.only(top: 59, bottom: 34),
        ),
        child: Builder(
          builder: (context) {
            height = koyzeSheetMaxHeight(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(height, 852 - 59 - 16);
  });

  testWidgets('sheet stays above the shell mini player', (tester) async {
    var sheetTaps = 0;
    var miniTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Navigator(
              onGenerateRoute: (settings) {
                return MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () {
                        showKoyzeSheet<void>(
                          context: context,
                          builder: (_) => SizedBox(
                            height: 240,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: TextButton(
                                onPressed: () => sheetTaps++,
                                child: const Text('sheet-bottom'),
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text('open-sheet'),
                    ),
                  ),
                );
              },
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 66,
                width: double.infinity,
                child: TextButton(
                  onPressed: () => miniTaps++,
                  child: const Text('mini-player'),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('sheet-bottom'));
    expect(sheetTaps, 1);
    expect(miniTaps, 0);
  });

  testWidgets('landscape option sheet scrolls instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(852, 393);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showKoyzeSheet<void>(
                context: context,
                builder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 8; i++)
                      SizedBox(
                        height: 56,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('option-$i'),
                        ),
                      ),
                  ],
                ),
              );
            },
            child: const Text('open-sheet'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('option-0'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('option-7'),
      80,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('option-7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet keeps a gap on both sides and below', (tester) async {
    const size = Size(390, 844);
    final rect = await _openSheetAndMeasure(tester, size);

    expect(rect.left, 12);
    expect(size.width - rect.right, 12);
    // 底部也留一条：只缩左右会让面板像被三条边夹住，四角都看不见圆角。
    expect(size.height - rect.bottom, 10);
  });

  testWidgets('sheet stops growing on wide screens', (tester) async {
    const size = Size(1024, 768);
    final rect = await _openSheetAndMeasure(tester, size);

    expect(rect.width, 640);
    expect(rect.left, (size.width - 640) / 2);
  });

  testWidgets('self-drawn sheet panels share the floating gap', (tester) async {
    // 播放队列这类自己画面板的弹层走 frosted: false，
    // 它们也必须拿到同样的左右离屏，否则一个弹层家族里两种边距。
    const size = Size(390, 844);
    final rect = await _openSheetAndMeasure(tester, size, frosted: false);

    expect(rect.left, 12);
    expect(size.width - rect.right, 12);
  });

  testWidgets('dialog panel never spans the viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showKoyzeDialog<void>(
                context: context,
                builder: (_) => KoyzeDialog(
                  title: const Text('删除播放列表？'),
                  content: const Text('这个操作无法撤销。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('open-dialog'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-dialog'));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(GlassSurface).first);
    expect(rect.left, greaterThanOrEqualTo(28));
    expect(390 - rect.right, greaterThanOrEqualTo(28));
  });
}
