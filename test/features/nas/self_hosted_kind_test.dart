import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/nas/domain/nas_config.dart';
import 'package:koyze/features/nas/domain/nas_kind.dart';
import 'package:koyze/features/nas/domain/self_hosted_kind.dart';
import 'package:koyze/features/nas/presentation/nas_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/subsonic/domain/subsonic_config.dart';
import 'package:koyze/features/subsonic/presentation/subsonic_library_screen.dart';
import 'package:koyze/features/subsonic/presentation/subsonic_provider.dart';
import 'package:koyze/features/subsonic/presentation/subsonic_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<StorageService> _freshStorage([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return StorageService.forTesting(await SharedPreferences.getInstance());
}

List<Override> _nasOverrides(StorageService storage) => [
      selfHostedKindStorageProvider.overrideWithValue(() async => storage),
      subsonicConnectedProvider.overrideWithValue(false),
      subsonicConfigProvider.overrideWithValue(SubsonicConfig.empty),
      subsonicLibrarySongsProvider.overrideWith(
        (ref) async => const <MusicItem>[],
      ),
      for (final kind in NasKind.values) ...[
        nasConnectedProvider(kind).overrideWithValue(false),
        nasConfigProvider(kind).overrideWithValue(NasConfig.empty(kind)),
        nasLibrarySongsProvider(kind).overrideWith(
          (ref) async => const <MusicItem>[],
        ),
      ],
    ];

void main() {
  test('library page source has no type chips; settings keeps them', () {
    final library = File(
      'lib/features/subsonic/presentation/subsonic_library_screen.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/subsonic/presentation/subsonic_settings_screen.dart',
    ).readAsStringSync();

    expect(library, isNot(contains('ChoiceChip')));
    expect(library, isNot(contains('SelfHostedKind.values')));
    expect(library, contains('selfHostedKindProvider'));
    expect(settings, contains('ChoiceChip'));
    expect(settings, contains('selfHostedKindProvider'));
  });

  test('selected self-hosted kind persists across notifier instances', () async {
    final storage = await _freshStorage();
    final first = SelfHostedKindNotifier(storage: () async => storage);
    await first.restored;
    expect(first.state, SelfHostedKind.subsonic);

    await first.select(SelfHostedKind.emby);
    expect(first.state, SelfHostedKind.emby);
    expect(storage.getString(selfHostedKindStorageKey), 'emby');

    final second = SelfHostedKindNotifier(storage: () async => storage);
    await second.restored;
    expect(second.state, SelfHostedKind.emby);
  });

  test('dirty stored kind falls back to subsonic', () async {
    final storage = await _freshStorage({
      selfHostedKindStorageKey: 'not-a-kind',
    });
    final notifier = SelfHostedKindNotifier(storage: () async => storage);
    await notifier.restored;
    expect(notifier.state, SelfHostedKind.subsonic);
  });

  testWidgets('library page has no type chips; settings keeps them', (
    tester,
  ) async {
    final storage = await _freshStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: _nasOverrides(storage),
        child: const MaterialApp(home: SubsonicLibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Subsonic'), findsNothing);
    expect(find.text('Emby'), findsNothing);
    expect(find.text('Jellyfin'), findsNothing);
    expect(find.text('Plex'), findsNothing);
    expect(find.text('群晖'), findsNothing);
    expect(find.text('去连接'), findsOneWidget);
  });

  testWidgets('settings chips switch the kind used by the library', (
    tester,
  ) async {
    final storage = await _freshStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: _nasOverrides(storage),
        child: const MaterialApp(home: SubsonicSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(5));
    expect(find.text('Subsonic'), findsOneWidget);
    expect(find.text('群晖'), findsOneWidget);

    await tester.tap(find.text('Emby'));
    await tester.pumpAndSettle();

    expect(storage.getString(selfHostedKindStorageKey), 'emby');
    expect(find.textContaining('连接 Emby'), findsWidgets);
  });
}
