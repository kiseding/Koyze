import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings page routes capture their tile expansion origin', () {
    final source = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();

    for (final route in [
      '/stats',
      '/duplicates',
      '/download',
      '/local-music',
      '/custom-source',
      '/sync',
    ]) {
      expect(
        RegExp(
          "context\\.push\\('$route'\\),\\s*captureExpandOrigin: true",
        ).hasMatch(source),
        isTrue,
        reason: '$route must return to its settings tile',
      );
    }
  });
}
