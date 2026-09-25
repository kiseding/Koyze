import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/lyric/domain/lyric.dart';
import 'package:koyze/features/lyric/presentation/lyric_provider.dart';
import 'package:koyze/features/lyric/presentation/lyric_view.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';

void main() {
  testWidgets('shows loading state while the current lyric request is pending',
      (tester) async {
    final pending = Completer<Lyrics>();
    await _pumpView(tester, (_) => pending.future);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading lyrics'), findsOneWidget);
    expect(find.text('No lyrics'), findsNothing);
  });

  testWidgets('shows safe actionable error without exposing exception details',
      (tester) async {
    await _pumpView(
      tester,
      (_) => Future<Lyrics>.error(
        StateError('Authorization: Bearer secret-token'),
      ),
    );
    await tester.pump();

    expect(find.text('Could not load lyrics'), findsOneWidget);
    expect(find.text('Check the connection and try again'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);
    expect(find.textContaining('Authorization'), findsNothing);
  });

  testWidgets('shows the existing empty state when loading returns no lyrics',
      (tester) async {
    await _pumpView(tester, (_) async => Lyrics.empty());
    await tester.pump();

    expect(find.text('No lyrics'), findsOneWidget);
    expect(find.text('Search lyrics'), findsOneWidget);
    expect(find.text('Could not load lyrics'), findsNothing);
  });

  testWidgets('error retry starts the injected loader and renders its result',
      (tester) async {
    final retried = Completer<Lyrics>();
    var calls = 0;
    await _pumpView(tester, (_) {
      if (calls++ == 0) {
        return Future<Lyrics>.error(StateError('first failure'));
      }
      return retried.future;
    });
    await tester.pump();

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(calls, 2);
    expect(find.text('Loading lyrics'), findsOneWidget);

    retried.complete(_lyrics('retry success'));
    await tester.pump();

    expect(find.text('retry success'), findsOneWidget);
    expect(find.text('Could not load lyrics'), findsNothing);
  });
}

Future<void> _pumpView(WidgetTester tester, LyricLoader loader) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMusicProvider.overrideWithValue(_music('A')),
        currentLineIndexProvider.overrideWithValue(-1),
        playerPositionProvider.overrideWith((_) => PositionNotifier(null)),
        lyricLoaderProvider.overrideWithValue(loader),
      ],
      child: const MaterialApp(
        home: Scaffold(body: LyricView()),
      ),
    ),
  );
}

MusicItem _music(String id) => MusicItem(
      id: id,
      name: id,
      singer: 'artist',
      source: 'tx',
      platform: 'tx',
    );

Lyrics _lyrics(String value) => Lyrics(
      raw: value,
      lines: [LyricLine(time: Duration.zero, text: value)],
    );
