import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings page routes capture their tile expansion origin', () {
    final source = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();

    for (final route in [
      '/stats',
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

    expect(source, isNot(contains('重复歌曲')));
    expect(source, isNot(contains('/duplicates')));
  });

  test('default search picker includes self-hosted and nas sources', () {
    final settings = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();
    final search = File(
      'lib/features/search/presentation/search_provider.dart',
    ).readAsStringSync();

    expect(settings, contains('allSearchSourcesProvider'));
    expect(settings, contains('platformPickerDescription'));
    expect(settings, contains('platformPickerIcon'));
    expect(settings, contains("case 'subsonic':"));
    expect(settings, contains("return 'NAS 乐库'"));
    expect(settings, isNot(contains("case 'emby':")));
    expect(settings, isNot(contains('static const _options')));

    expect(search, contains("SearchSourceItem(id: 'subsonic', name: 'NAS')"));
    expect(search, contains('_searchConnectedNas'));
    expect(search, isNot(contains('kind.shortSearchLabel')));
    expect(search, isNot(contains('if (connected) SearchSourceItem')));
    expect(
      search,
      isNot(contains('if (ref.watch(nasConnectedProvider(kind)))')),
    );
  });
}
