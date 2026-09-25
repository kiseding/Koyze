import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/logging/app_log.dart';
import 'package:koyze/features/settings/presentation/app_log_screen.dart';

void main() {
  testWidgets('shows live entries and enables copy when available', (
    tester,
  ) async {
    final log = AppLog();
    log.record('audio', 'route changed');

    await tester.pumpWidget(MaterialApp(home: AppLogScreen(log: log)));

    expect(find.textContaining('route changed'), findsOneWidget);
    expect(find.byTooltip('Copy all'), findsOneWidget);
    final copyButton = find.widgetWithIcon(IconButton, Icons.copy_all_outlined);
    expect(copyButton, findsOneWidget);
    expect(tester.widget<IconButton>(copyButton).onPressed, isNotNull);
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
}
