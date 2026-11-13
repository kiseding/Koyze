import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/app_notification.dart';

void main() {
  testWidgets('error notification is a live region with keyboard dismiss', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppNotificationHost(child: Scaffold(body: Text('content'))),
      ),
    );

    expect(
      showAppNotification('无法收藏', type: AppNotificationType.error),
      isTrue,
    );
    await tester.pump();

    final liveRegion = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((widget) => widget.properties.liveRegion == true);
    expect(liveRegion.properties.label, 'Error: 无法收藏');
    // 关闭按钮的无障碍标签走 Semantics 而不是 Tooltip：横幅挂在
    // Navigator 之上（没有 Overlay 祖先），带 tooltip 会直接抛异常。
    final dismissButton = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((widget) => widget.properties.label == 'Dismiss')
        .toList();
    expect(dismissButton, hasLength(1));
    expect(dismissButton.single.properties.button, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('无法收藏'), findsNothing);
  });

  /// 生产环境的挂载位置：`MaterialApp.builder` 里，也就是 Navigator **之上**。
  /// 那里没有 Overlay 祖先，横幅内任何 Tooltip 都会抛
  /// `No Overlay widget found`，debug 下整页变红屏。
  ///
  /// 上面的测试用的是 `home:`（Navigator 内部，有 Overlay），所以历史上
  /// 一直是通过的——这个用例专门按生产的结构挡回归。
  testWidgets('banner survives without an Overlay ancestor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppNotificationHost(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('content')),
      ),
    );

    expect(showAppNotification('已收藏'), isTrue);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('已收藏'), findsOneWidget);
  });

  testWidgets('notification timeout pauses while focused', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppNotificationHost(child: Scaffold(body: Text('content'))),
      ),
    );

    expect(showAppNotification('处理中'), isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('处理中'), findsOneWidget);
  });

  testWidgets('notification stays readable then dismisses automatically', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppNotificationHost(child: Scaffold(body: Text('content'))),
      ),
    );

    expect(showAppNotification('已更新'), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('已更新'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('已更新'), findsNothing);
  });
}
