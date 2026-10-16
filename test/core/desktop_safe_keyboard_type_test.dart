import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/widgets/auto_text_input.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Windows URL fields use a text keyboard so colon is not semicolon', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(desktopSafeKeyboardType(TextInputType.url), TextInputType.text);
    expect(
      desktopSafeKeyboardType(TextInputType.emailAddress),
      TextInputType.text,
    );
    expect(desktopSafeKeyboardType(TextInputType.text), TextInputType.text);
  });

  test('mobile URL fields keep the URL keyboard', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(desktopSafeKeyboardType(TextInputType.url), TextInputType.url);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(desktopSafeKeyboardType(TextInputType.url), TextInputType.url);
  });

  test('first-launch and URL dialogs go through the desktop-safe helper', () {
    const files = [
      'lib/features/sync/presentation/startup_cloud_login_prompt.dart',
      'lib/features/sync/presentation/sync_screen.dart',
      'lib/features/custom_source/presentation/custom_source_screen.dart',
      'lib/features/playlist/presentation/playlist_screen.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, contains('desktopSafeKeyboardType'));
      expect(source, isNot(contains('keyboardType: TextInputType.url')));
    }
  });
}
