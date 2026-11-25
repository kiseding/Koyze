import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/search/presentation/search_provider.dart';
import 'package:koyze/core/music_source/platform/tx_source.dart';

void main() {
  test('QQ smartbox parser reads ordered song singer and album suggestions', () {
    final suggestions = TxSource.parseSearchSuggestions({
      'code': 0,
      'data': {
        'order': ['singer', 'song', 'album'],
        'singer': {
          'itemlist': [
            {'name': '周杰伦', 'mid': 'singer-mid'},
          ],
        },
        'song': {
          'itemlist': [
            {'name': '晴天', 'mid': 'song-mid'},
            {'name': '周杰伦', 'mid': 'duplicate'},
          ],
        },
        'album': {
          'itemlist': [
            {'name': '叶惠美', 'mid': 'album-mid'},
          ],
        },
      },
    });

    expect(suggestions.map((item) => (item.text, item.type)), [
      ('周杰伦', 'singer'),
      ('晴天', 'song'),
      ('叶惠美', 'album'),
    ]);
  });

  test('search suggestion requests reject stale results and source changes', () async {
    final old = Completer<List<SearchSuggestion>>();
    final current = Completer<List<SearchSuggestion>>();
    var selectedSource = 'tx';
    final notifier = SearchSuggestionsNotifier(
      load: (query, source) => query == 'old' ? old.future : current.future,
      readSelectedSource: () => selectedSource,
    );
    addTearDown(notifier.dispose);

    final oldRequest = notifier.suggest('old');
    final currentRequest = notifier.suggest('current');
    current.complete([const SearchSuggestion(text: 'current hit', type: 'song')]);
    await currentRequest;
    old.complete([const SearchSuggestion(text: 'stale hit', type: 'song')]);
    await oldRequest;

    expect(notifier.value.query, 'current');
    expect(notifier.value.items.single.text, 'current hit');

    final pending = Completer<List<SearchSuggestion>>();
    final sourceNotifier = SearchSuggestionsNotifier(
      load: (query, source) => pending.future,
      readSelectedSource: () => selectedSource,
    );
    addTearDown(sourceNotifier.dispose);
    final pendingRequest = sourceNotifier.suggest('switch');
    selectedSource = 'wy';
    sourceNotifier.reset();
    pending.complete([const SearchSuggestion(text: 'wrong source', type: 'song')]);
    await pendingRequest;
    expect(sourceNotifier.value.items, isEmpty);
  });

  test('search sources expose a single NAS entry for all self-hosted servers', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final sources = container.read(allSearchSourcesProvider);
    expect(
      sources.map((source) => source.id).toList(),
      [
        'all',
        'tx',
        'kw',
        'wy',
        'kg',
        'local',
        'favorites',
        'subsonic',
      ],
    );
    expect(sources.singleWhere((source) => source.id == 'subsonic').name, 'NAS');
    expect(sources.map((source) => source.name), isNot(contains('Emby')));
    expect(sources.map((source) => source.name), isNot(contains('Jellyfin')));
    expect(sources.map((source) => source.name), isNot(contains('Plex')));
    expect(sources.map((source) => source.name), isNot(contains('群晖')));
  });

  test('late first-page result cannot overwrite a newer query', () async {
    final first = Completer<List<MusicItem>>();
    final second = Completer<List<MusicItem>>();
    var source = 'tx';
    final notifier = SearchNotifier(
      (query, sourceId, page) => query == 'old' ? first.future : second.future,
      () => source,
    );
    addTearDown(notifier.dispose);

    final oldSearch = notifier.search('old');
    source = 'kw';
    final newSearch = notifier.search('new');
    second.complete([_item('new')]);
    await newSearch;
    first.complete([_item('old')]);
    await oldSearch;

    expect(notifier.value.query, 'new');
    expect(notifier.value.sourceId, 'kw');
    expect(notifier.value.generation, 2);
    expect(notifier.value.items.single.id, 'new');
  });

  test('loadMore uses state query and source snapshots', () async {
    final calls = <({String query, String source, int page})>[];
    var selectedSource = 'tx';
    final notifier = SearchNotifier((query, source, page) async {
      calls.add((query: query, source: source, page: page));
      return List.generate(20, (index) => _item('$query-$page-$index'));
    }, () => selectedSource);
    addTearDown(notifier.dispose);

    await notifier.search('stored');
    selectedSource = 'wy';
    await notifier.loadMore();

    expect(calls, [
      (query: 'stored', source: 'tx', page: 1),
      (query: 'stored', source: 'tx', page: 2),
    ]);
    expect(notifier.value.page, 2);
    expect(notifier.value.items, hasLength(40));
  });

  test('concurrent loadMore calls share the in-flight page', () async {
    final pageTwo = Completer<List<MusicItem>>();
    var pageTwoCalls = 0;
    final notifier = SearchNotifier((query, source, page) async {
      if (page == 1) {
        return List.generate(20, (index) => _item('first-$index'));
      }
      pageTwoCalls++;
      return pageTwo.future;
    }, () => 'tx');
    addTearDown(notifier.dispose);
    await notifier.search('stored');

    final firstLoadMore = notifier.loadMore();
    final duplicateLoadMore = notifier.loadMore();
    pageTwo.complete([_item('more')]);
    await Future.wait([firstLoadMore, duplicateLoadMore]);

    expect(pageTwoCalls, 1);
    expect(notifier.value.page, 2);
  });

  test('reset invalidates an in-flight request', () async {
    final result = Completer<List<MusicItem>>();
    final notifier = SearchNotifier(
      (query, source, page) => result.future,
      () => 'tx',
    );
    addTearDown(notifier.dispose);

    final search = notifier.search('old');
    notifier.reset();
    result.complete([_item('old')]);
    await search;

    expect(notifier.value.query, isEmpty);
    expect(notifier.value.items, isEmpty);
    expect(notifier.value.isLoading, isFalse);
  });

  test('stale error cannot overwrite a newer success', () async {
    final first = Completer<List<MusicItem>>();
    final second = Completer<List<MusicItem>>();
    final notifier = SearchNotifier(
      (query, source, page) => query == 'old' ? first.future : second.future,
      () => 'tx',
    );
    addTearDown(notifier.dispose);

    final oldSearch = notifier.search('old');
    final newSearch = notifier.search('new');
    second.complete([_item('new')]);
    await newSearch;
    first.completeError(StateError('stale failure'));
    await oldSearch;

    expect(notifier.value.items.single.id, 'new');
    expect(notifier.value.error, isNull);
  });

  test('current error is stored and search future does not throw', () async {
    final notifier = SearchNotifier(
      (query, source, page) => Future.error(StateError('network failure')),
      () => 'tx',
    );
    addTearDown(notifier.dispose);

    await expectLater(notifier.search('current'), completes);

    expect(notifier.value.query, 'current');
    expect(notifier.value.sourceId, 'tx');
    expect(notifier.value.isLoading, isFalse);
    expect(notifier.value.error, contains('network failure'));
  });

  test('dispose invalidates an in-flight request without async errors',
      () async {
    final result = Completer<List<MusicItem>>();
    final notifier = SearchNotifier(
      (query, source, page) => result.future,
      () => 'tx',
    );

    final search = notifier.search('old');
    notifier.dispose();
    result.complete([_item('old')]);

    await expectLater(search, completes);
  });

  test('search prepends exact local matches', () async {
    final local = _item('local-hit');
    final notifier = SearchNotifier(
      (query, sourceId, page) async => [_item('online-hit')],
      () => 'tx',
      (query, limit) async => [local],
    );
    addTearDown(notifier.dispose);

    await notifier.search('hit');

    expect(notifier.value.localMatches, hasLength(1));
    expect(notifier.value.localMatches.single.id, 'local-hit');
    expect(notifier.value.items.single.id, 'online-hit');
  });
}

MusicItem _item(String id) => MusicItem(
      id: id,
      name: id,
      singer: 'artist',
      source: 'tx',
      platform: 'tx',
    );
