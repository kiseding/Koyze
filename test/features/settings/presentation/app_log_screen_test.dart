import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/logging/app_log.dart';
import 'package:koyze/features/settings/presentation/app_log_screen.dart';

void main() {
  testWidgets('shows live entries and enables copy when available', (
    tester,
  ) async {
    final log = AppLog(startRecording: true);
    log.record('audio', 'route changed');

    await tester.pumpWidget(MaterialApp(home: AppLogScreen(log: log)));

    expect(find.textContaining('route changed'), findsOneWidget);
    // 复制按钮只复制当前标签下的日志，文案也随之从「Copy all」改成
    // 「Copy current tab」——写着「全部」而只给一部分是在骗人。
    expect(find.byTooltip('Copy current tab'), findsOneWidget);
    final copyButton = find.widgetWithIcon(IconButton, Icons.copy_all_outlined);
    expect(copyButton, findsOneWidget);
    expect(tester.widget<IconButton>(copyButton).onPressed, isNotNull);
  });

  testWidgets('records nothing until the overlay is opened', (tester) async {
    final log = AppLog.instance;
    log.stop();
    log.clear();
    addTearDown(log.clear);
    log.record('custom_source.import', 'recorded before opening');
    expect(log.exportText(), isEmpty);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDiagnosticLogOverlay(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    expect(log.isActive, isTrue);

    log.record('custom_source.import', 'local file import failed');
    await tester.pump();

    expect(find.textContaining('recorded before opening'), findsNothing);
    expect(find.textContaining('local file import failed'), findsOneWidget);

    await tester.tap(find.byTooltip('Close diagnostics'));
    await tester.pump();
    expect(log.isActive, isFalse);
  });

  testWidgets(
    'diagnostic overlay minimizes while recording and stops on close',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDiagnosticLogOverlay(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      expect(AppLog.instance.isActive, isTrue);
      expect(find.text('Diagnostics'), findsOneWidget);

      await tester.tap(find.byTooltip('Minimize'));
      await tester.pump();
      expect(find.textContaining('Log '), findsOneWidget);
      expect(AppLog.instance.isActive, isTrue);

      await tester.tap(find.textContaining('Log '));
      await tester.pump();
      await tester.tap(find.byTooltip('Close diagnostics'));
      await tester.pump();
      expect(find.text('Diagnostics'), findsNothing);
      expect(AppLog.instance.isActive, isFalse);
    },
  );

  testWidgets('filters down to warnings and errors', (tester) async {
    final log = AppLog(startRecording: true);
    log.record('network', 'quiet info');
    log.record('network', 'slow response', level: AppLogLevel.warning);
    log.record('network', 'request failed', level: AppLogLevel.error);

    await tester.pumpWidget(MaterialApp(home: AppLogScreen(log: log)));

    expect(find.textContaining('quiet info'), findsOneWidget);

    await tester.tap(find.textContaining('Errors'));
    await tester.pump();
    expect(find.textContaining('request failed'), findsOneWidget);
    expect(find.textContaining('quiet info'), findsNothing);
    expect(find.textContaining('slow response'), findsNothing);

    await tester.tap(find.textContaining('Warnings'));
    await tester.pump();
    expect(find.textContaining('slow response'), findsOneWidget);
    expect(find.textContaining('request failed'), findsNothing);
  });

  testWidgets('复制只取当前选中标签，不是全量日志', (tester) async {
    // 剪贴板在测试里没有真实平台通道，直接截获 setData 的入参。
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final log = AppLog(startRecording: true);
    log.record('network', 'quiet info');
    log.record('network', 'slow response', level: AppLogLevel.warning);
    log.record('network', 'request failed', level: AppLogLevel.error);

    await tester.pumpWidget(MaterialApp(home: AppLogScreen(log: log)));

    // 先切到「错误」标签，再点复制。
    await tester.tap(find.textContaining('Errors'));
    await tester.pump();
    await tester.tap(find.byTooltip('Copy current tab'));
    await tester.pump();

    expect(copied, isNotNull, reason: '复制按钮应该把内容写进剪贴板');
    expect(
      copied,
      contains('request failed'),
      reason: '当前标签里的那条错误必须在',
    );
    expect(
      copied,
      isNot(contains('quiet info')),
      reason: '没被当前标签筛中的 info 不该被复制出去',
    );
    expect(
      copied,
      isNot(contains('slow response')),
      reason: '没被当前标签筛中的 warning 不该被复制出去',
    );
  });

  testWidgets('返回键等同于关闭：按下后立即停止记录', (tester) async {
    final log = AppLog.instance;
    log.stop();
    log.clear();
    addTearDown(log.clear);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDiagnosticLogOverlay(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    expect(log.isActive, isTrue);

    // 面板挂在 rootOverlay 上、不是 Route，所以系统返回键原本跟它无关——
    // 用户按返回会以为退出了，实际记录还在继续。这里锁住「返回 = 关闭」。
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump();

    expect(
      log.isActive,
      isFalse,
      reason: '按返回键之后不该还在后台记录',
    );
    expect(find.text('Diagnostics'), findsNothing, reason: '面板本身也要消失');
  });
}
