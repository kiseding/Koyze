// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:koyze/core/ui/responsive_layout.dart';

void main() {
  group('LayoutConfig', () {
    test('should detect mobile layout', () {
      final config = LayoutConfig.fromConstraints(
        BoxConstraints(maxWidth: 400, maxHeight: 800),
      );

      expect(config.isMobile, isTrue);
      expect(config.isTablet, isFalse);
      expect(config.isDesktop, isFalse);
      expect(config.gridColumns, equals(2));
    });

    test('should detect tablet layout', () {
      final config = LayoutConfig.fromConstraints(
        BoxConstraints(maxWidth: 768, maxHeight: 1024),
      );

      expect(config.isMobile, isFalse);
      expect(config.isTablet, isTrue);
      expect(config.isDesktop, isFalse);
      expect(config.gridColumns, equals(3));
    });

    test('should detect desktop layout', () {
      final config = LayoutConfig.fromConstraints(
        BoxConstraints(maxWidth: 1920, maxHeight: 1080),
      );

      expect(config.isMobile, isFalse);
      expect(config.isTablet, isFalse);
      expect(config.isDesktop, isTrue);
      expect(config.gridColumns, equals(4));
    });

    test('should apply correct padding for mobile', () {
      final config = LayoutConfig.fromConstraints(
        BoxConstraints(maxWidth: 400, maxHeight: 800),
      );

      expect(config.pagePadding.horizontal, equals(LayoutSpacing.md * 2));
      expect(config.pagePadding.vertical, equals(LayoutSpacing.sm * 2));
    });

    test('should apply correct padding for desktop', () {
      final config = LayoutConfig.fromConstraints(
        BoxConstraints(maxWidth: 1920, maxHeight: 1080),
      );

      expect(config.pagePadding.horizontal, equals(LayoutSpacing.lg * 2));
      expect(config.pagePadding.vertical, equals(LayoutSpacing.md * 2));
    });

    test('should limit content width', () {
      final config = LayoutConfig.fromConstraints(
        BoxConstraints(maxWidth: 2000, maxHeight: 1200),
      );

      expect(config.contentMaxWidth, lessThanOrEqualTo(1200));
    });
  });

  group('ResponsiveLayout', () {
    testWidgets('should provide correct config', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      LayoutConfig? capturedConfig;

      await tester.pumpWidget(
        MaterialApp(
          home: ResponsiveLayout(
            builder: (context, config) {
              capturedConfig = config;
              return Container();
            },
          ),
        ),
      );

      expect(capturedConfig, isNotNull);
      expect(capturedConfig!.isMobile, isTrue); // Test environment is mobile-sized
    });
  });

  group('ModernCard', () {
    testWidgets('should render with default styling', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModernCard(
              child: Text('Test Card'),
            ),
          ),
        ),
      );

      expect(find.text('Test Card'), findsOneWidget);
    });

    testWidgets('should handle tap events', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModernCard(
              onTap: () => tapped = true,
              child: Text('Tap Me'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Me'));
      expect(tapped, isTrue);
    });

    testWidgets('should apply custom padding', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModernCard(
              padding: EdgeInsets.all(32),
              child: Text('Padded'),
            ),
          ),
        ),
      );

      expect(find.text('Padded'), findsOneWidget);
    });
  });

  group('MusicCard', () {
    testWidgets('should display title and subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MusicCard(
              title: 'Test Song',
              subtitle: 'Test Artist',
            ),
          ),
        ),
      );

      expect(find.text('Test Song'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);
    });

    testWidgets('should show play button when provided', (tester) async {
      bool playTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MusicCard(
              title: 'Song',
              subtitle: 'Artist',
              onPlay: () => playTapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.play_arrow));
      expect(playTapped, isTrue);
    });
  });

  group('OptimizedSongListItem', () {
    testWidgets('should display song info', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptimizedSongListItem(
              title: 'Test Song',
              artist: 'Test Artist',
              album: 'Test Album',
              duration: Duration(minutes: 3, seconds: 45),
            ),
          ),
        ),
      );

      expect(find.text('Test Song'), findsOneWidget);
      expect(find.text('Test Artist · Test Album'), findsOneWidget);
      expect(find.text('3:45'), findsOneWidget);
    });

    testWidgets('should highlight playing song', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptimizedSongListItem(
              title: 'Playing Song',
              artist: 'Artist',
              isPlaying: true,
            ),
          ),
        ),
      );

      expect(find.text('Playing Song'), findsOneWidget);
    });

    testWidgets('should handle tap events', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptimizedSongListItem(
              title: 'Song',
              artist: 'Artist',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Song'));
      expect(tapped, isTrue);
    });
  });

  group('SectionHeader', () {
    testWidgets('should display title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionHeader(title: 'Test Section'),
          ),
        ),
      );

      expect(find.text('Test Section'), findsOneWidget);
    });

    testWidgets('should show action button when provided', (tester) async {
      bool actionTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionHeader(
              title: 'Section',
              actionLabel: 'View All',
              onAction: () => actionTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('View All'), findsOneWidget);
      await tester.tap(find.text('View All'));
      expect(actionTapped, isTrue);
    });
  });

  group('LayoutSpacing', () {
    test('should follow 8dp grid', () {
      expect(LayoutSpacing.xs, equals(4));
      expect(LayoutSpacing.sm, equals(8));
      expect(LayoutSpacing.md, equals(16));
      expect(LayoutSpacing.lg, equals(24));
      expect(LayoutSpacing.xl, equals(32));
      expect(LayoutSpacing.xxl, equals(48));
      expect(LayoutSpacing.xxxl, equals(64));

      // All values should be multiples of 4
      expect(LayoutSpacing.xs % 4, equals(0));
      expect(LayoutSpacing.sm % 4, equals(0));
      expect(LayoutSpacing.md % 4, equals(0));
      expect(LayoutSpacing.lg % 4, equals(0));
      expect(LayoutSpacing.xl % 4, equals(0));
    });
  });

  group('LayoutBreakpoints', () {
    test('should define standard breakpoints', () {
      expect(LayoutBreakpoints.mobile, equals(600));
      expect(LayoutBreakpoints.tablet, equals(900));
      expect(LayoutBreakpoints.desktop, equals(1200));
      expect(LayoutBreakpoints.wide, equals(1600));
    });
  });
}
