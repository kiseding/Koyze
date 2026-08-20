import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main resolver grants exclusivity only to playback generations', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('exclusive: resolutionGeneration is int'));
    expect(source, isNot(contains('mediaItem.value?.id == mediaId;')));
  });

  test(
    'startup hydrates download and playback settings before restoration',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final wifiHydration = source.indexOf(
        'read(wifiOnlyDownloadProvider.notifier)',
      );
      final downloadInit = source.indexOf(
        'read(downloadServiceProvider).init()',
      );
      final qualityHydration = source.indexOf('lxHandler.preferredQuality =');
      final restore = source.indexOf('restorePlaybackSession(');

      expect(wifiHydration, inInclusiveRange(0, downloadInit - 1));
      expect(qualityHydration, inInclusiveRange(0, restore - 1));
    },
  );
}
