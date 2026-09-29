// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:koyze/core/accessibility/a11y_helpers.dart';

void main() {
  group('A11yHelper', () {
    test('should calculate contrast ratio correctly', () {
      // Black on white
      final ratio1 = A11yHelper.calculateContrastRatio(Colors.black, Colors.white);
      expect(ratio1, greaterThan(20.0)); // Should be 21:1

      // White on black
      final ratio2 = A11yHelper.calculateContrastRatio(Colors.white, Colors.black);
      expect(ratio2, greaterThan(20.0)); // Should be 21:1

      // Same color
      final ratio3 = A11yHelper.calculateContrastRatio(Colors.blue, Colors.blue);
      expect(ratio3, equals(1.0)); // 1:1
    });

    test('should validate WCAG AA compliance (4.5:1)', () {
      // Black on white passes
      expect(A11yHelper.meetsWCAG_AA(Colors.black, Colors.white), isTrue);

      // Light grey on white fails
      expect(A11yHelper.meetsWCAG_AA(Colors.grey[300]!, Colors.white), isFalse);

      // Dark blue on white passes
      expect(A11yHelper.meetsWCAG_AA(Color(0xFF0000AA), Colors.white), isTrue);
    });

    test('should validate WCAG AAA compliance (7:1)', () {
      // Black on white passes
      expect(A11yHelper.meetsWCAG_AAA(Colors.black, Colors.white), isTrue);

      // Medium grey on white fails
      expect(A11yHelper.meetsWCAG_AAA(Colors.grey[600]!, Colors.white), isFalse);

      // Very dark text on white passes
      expect(A11yHelper.meetsWCAG_AAA(Colors.grey[900]!, Colors.white), isTrue);
    });

    testWidgets('should scale text based on accessibility settings', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final scaledSize = A11yHelper.getAccessibleTextSize(context, 16.0);
              return Text(
                'Test',
                style: TextStyle(fontSize: scaledSize),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should respect text scale factor
      expect(find.text('Test'), findsOneWidget);
    });
  });

  group('AccessibleButton', () {
    testWidgets('should have semantic label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleButton(
              semanticLabel: '播放音乐',
              onPressed: () {},
              child: Text('Play'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should find semantics with label
      expect(
        find.bySemanticsLabel('播放音乐'),
        findsOneWidget,
      );
    });

    testWidgets('should be marked as button in semantics tree', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleButton(
              semanticLabel: 'Test Button',
              onPressed: () {},
              child: Text('Click me'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.bySemanticsLabel('Test Button'));
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    });

    testWidgets('should show tooltip on hover', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleButton(
              semanticLabel: 'Test',
              tooltip: 'This is a tooltip',
              onPressed: () {},
              child: Text('Hover me'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Long press to show tooltip
      await tester.longPress(find.text('Hover me'));
      await tester.pumpAndSettle();

      expect(find.text('This is a tooltip'), findsOneWidget);
    });
  });

  group('AccessibleTextField', () {
    testWidgets('should have semantic label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleTextField(
              labelText: '用户名',
              semanticLabel: '请输入用户名',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('请输入用户名'), findsOneWidget);
    });

    testWidgets('should support text input', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleTextField(
              controller: controller,
              labelText: 'Name',
              semanticLabel: 'Enter your name',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter text
      await tester.enterText(find.byType(TextField), 'John Doe');
      expect(controller.text, equals('John Doe'));
    });
  });

  group('AccessibleMusicPlayerControls', () {
    testWidgets('should announce current song', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleMusicPlayerControls(
              isPlaying: true,
              currentSongTitle: '测试歌曲',
              onPlayPause: () {},
              onNext: () {},
              onPrevious: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should have semantic container with song info
      final semantics = tester.getSemantics(
        find.byType(AccessibleMusicPlayerControls),
      );
      expect(semantics.label, contains('测试歌曲'));
    });

    testWidgets('should have accessible play/pause button', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleMusicPlayerControls(
              isPlaying: false,
              currentSongTitle: 'Test Song',
              onPlayPause: () => tapped = true,
              onNext: () {},
              onPrevious: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find and tap play button
      await tester.tap(find.bySemanticsLabel('播放'));
      expect(tapped, isTrue);
    });

    testWidgets('should change button label based on play state', (tester) async {
      bool isPlaying = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: AccessibleMusicPlayerControls(
                  isPlaying: isPlaying,
                  currentSongTitle: 'Test',
                  onPlayPause: () => setState(() => isPlaying = !isPlaying),
                  onNext: () {},
                  onPrevious: () {},
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially should show "播放"
      expect(find.bySemanticsLabel('播放'), findsOneWidget);

      // Tap to play
      await tester.tap(find.bySemanticsLabel('播放'));
      await tester.pumpAndSettle();

      // Should now show "暂停"
      expect(find.bySemanticsLabel('暂停'), findsOneWidget);
    });
  });

  group('Contrast checking', () {
    test('should detect insufficient contrast', () {
      // Light text on light background
      final passes = A11yHelper.meetsWCAG_AA(
        Colors.grey[400]!,
        Colors.white,
      );
      
      expect(passes, isFalse);
    });

    test('should validate Material theme colors', () {
      final colorScheme = ColorScheme.fromSeed(
        seedColor: Color(0xFF6750A4),
        brightness: Brightness.light,
      );

      // Primary text on surface
      expect(
        A11yHelper.meetsWCAG_AA(
          colorScheme.onSurface,
          colorScheme.surface,
        ),
        isTrue,
      );

      // Primary text on primary container
      expect(
        A11yHelper.meetsWCAG_AA(
          colorScheme.onPrimaryContainer,
          colorScheme.primaryContainer,
        ),
        isTrue,
      );
    });
  });
}
