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
      '/subsonic-settings',
      '/equalizer',
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

  test('default search picker follows connected search sources', () {
    final source = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();

    expect(source, contains('allSearchSourcesProvider'));
    expect(source, contains('platformPickerDescription'));
    expect(source, contains('platformPickerIcon'));
    expect(source, contains("case 'subsonic':"));
    expect(source, contains("case 'emby':"));
    expect(source, contains("case 'audiostation':"));
    expect(source, contains("return '自建乐库'"));
    expect(source, isNot(contains('static const _options')));
  });
}
