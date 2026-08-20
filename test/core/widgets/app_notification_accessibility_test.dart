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
    expect(liveRegion.properties.label, '错误: 无法收藏');
    expect(find.byTooltip('关闭通知'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('无法收藏'), findsNothing);
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
