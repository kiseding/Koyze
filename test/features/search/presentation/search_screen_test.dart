import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/search/presentation/search_provider.dart';
import 'package:koyze/features/search/presentation/search_screen.dart';

void main() {
  test('pagination keeps a stable result list key', () {
    final source = File(
      'lib/features/search/presentation/search_screen.dart',
    ).readAsStringSync();

    expect(source, contains("ValueKey('results-\${searchState.generation}')"));
    expect(source, isNot(contains('searchState.isLoading}')));
  });

  test('search results use clamping scroll physics', () {
    final source = File(
      'lib/features/search/presentation/search_screen.dart',
    ).readAsStringSync();

    expect(source, contains('physics: const ClampingScrollPhysics()'));
  });

  testWidgets('search screen renders history and hot list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchStateProvider.overrideWith(
            (ref) => SearchNotifier(
              (query, sourceId, page) async => const [],
              () => 'tx',
            ),
          ),
          hotSearchProvider.overrideWith((ref) async => const ['热歌1']),
          searchHistoryProvider.overrideWith((ref) => SearchHistoryNotifier()),
          allSearchSourcesProvider.overrideWith(
            (ref) => [
              SearchSourceItem(id: 'all', name: '全网'),
              SearchSourceItem(id: 'tx', name: 'QQ'),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('热搜榜'), findsOneWidget);
    expect(find.text('热歌1'), findsOneWidget);
    expect(find.text('搜索'), findsWidgets);
  });

  testWidgets('search error exposes retry action', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchStateProvider.overrideWith(
            (ref) => SearchNotifier((query, sourceId, page) async {
              attempts++;
              throw StateError('offline');
            }, () => 'tx'),
          ),
          hotSearchProvider.overrideWith((ref) async => const []),
          searchHistoryProvider.overrideWith((ref) => SearchHistoryNotifier()),
          allSearchSourcesProvider.overrideWith(
            (ref) => [SearchSourceItem(id: 'tx', name: 'QQ')],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    await tester.enterText(find.byType(TextField), 'test');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('song results show a favorite button that toggles favorite', (
    tester,
  ) async {
    final song = MusicItem(
      id: 's1',
      name: '稻香',
      singer: '周杰伦',
      album: '魔杰座',
      duration: const Duration(seconds: 240),
      source: 'tx',
      platform: 'tx',
    );
    var toggled = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchStateProvider.overrideWith(
            (ref) => SearchNotifier(
              (query, sourceId, page) async => [song],
              () => 'tx',
            ),
          ),
          hotSearchProvider.overrideWith((ref) async => const []),
          searchHistoryProvider.overrideWith((ref) => SearchHistoryNotifier()),
          allSearchSourcesProvider.overrideWith(
            (ref) => [SearchSourceItem(id: 'tx', name: 'QQ')],
          ),
          isSongFavoriteProvider.overrideWith((ref, id) async => false),
          toggleFavoriteProvider.overrideWith(
            (ref) =>
                (MusicItem item) async => toggled++,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    await tester.enterText(find.byType(TextField), '稻香');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('稻香'), findsNWidgets(2));
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsOneWidget);

    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();
    expect(toggled, 1);
  });
}
