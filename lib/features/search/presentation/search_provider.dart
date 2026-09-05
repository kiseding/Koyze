import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/music_source_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../player/domain/music_item.dart';
import '../../custom_source/presentation/custom_source_provider.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';

final musicSourceServiceProvider = Provider<MusicSourceService>((ref) {
  final customSourceService = ref.watch(customSourceServiceProvider);
  final service = MusicSourceService(customSourceService);
  ref.onDispose(service.dispose);
  return service;
});

// 音源平台模型
class SearchSourceItem {
  final String id;
  final String name;

  SearchSourceItem({required this.id, required this.name});
}

// 桌面版固定的搜索平台列表
final allSearchSourcesProvider = Provider<List<SearchSourceItem>>((ref) {
  return [
    SearchSourceItem(id: 'all', name: '全网'),
    SearchSourceItem(id: 'tx', name: 'QQ'),
    SearchSourceItem(id: 'kw', name: '酷我'),
    SearchSourceItem(id: 'wy', name: '网易'),
    SearchSourceItem(id: 'local', name: '本地'),
    SearchSourceItem(id: 'favorites', name: '收藏'),
  ];
});

final searchQueryProvider = StateProvider<String>((ref) => '');
// 默认腾讯；设置页可改 defaultSearchPlatform 并同步到此
final selectedSourceIdProvider = StateProvider<String>(
  (ref) => ref.watch(defaultSearchPlatformProvider),
);

// 搜索状态类
class SearchState {
  final List<MusicItem> items;
  final List<MusicItem> localMatches;
  final int page;
  final int generation;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  final String query;
  final String sourceId;

  SearchState({
    this.items = const [],
    this.localMatches = const [],
    this.page = 1,
    this.generation = 0,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
    this.query = '',
    this.sourceId = '',
  });

  SearchState copyWith({
    List<MusicItem>? items,
    List<MusicItem>? localMatches,
    int? page,
    int? generation,
    bool? isLoading,
    bool? hasMore,
    String? error,
    String? query,
    String? sourceId,
  }) {
    return SearchState(
      items: items ?? this.items,
      localMatches: localMatches ?? this.localMatches,
      page: page ?? this.page,
      generation: generation ?? this.generation,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      query: query ?? this.query,
      sourceId: sourceId ?? this.sourceId,
    );
  }
}

typedef SearchLoader =
    Future<List<MusicItem>> Function(String query, String sourceId, int page);

/// 本地完全匹配查询：返回标题与关键词完全一致的本地歌曲（最多 [limit] 首）。
typedef LocalMatchLoader =
    Future<List<MusicItem>> Function(String query, int limit);

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._load, this._readSelectedSource, {this._loadLocalMatches})
    : super(SearchState());

  final SearchLoader _load;
  final String Function() _readSelectedSource;
  final LocalMatchLoader? _loadLocalMatches;
  int _generation = 0;

  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    final generation = ++_generation;
    if (query.isEmpty) {
      state = SearchState(generation: generation);
      return;
    }
    final sourceId = _readSelectedSource();
    state = SearchState(
      generation: generation,
      isLoading: true,
      query: query,
      sourceId: sourceId,
    );
    if (sourceId != 'local' && sourceId != 'favorites') {
      unawaited(_loadSupplementalLocalMatches(generation, query, sourceId));
    }
    await _loadPage(
      generation: generation,
      query: query,
      sourceId: sourceId,
      page: 1,
      append: false,
    );
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.query.isEmpty) return;
    final generation = state.generation;
    final query = state.query;
    final sourceId = state.sourceId;
    final page = state.page + 1;
    state = state.copyWith(isLoading: true, error: null);
    await _loadPage(
      generation: generation,
      query: query,
      sourceId: sourceId,
      page: page,
      append: true,
    );
  }

  Future<void> _loadSupplementalLocalMatches(
    int generation,
    String query,
    String sourceId,
  ) async {
    final localMatches = await _loadLocalMatches?.call(query, 5) ?? const [];
    if (_owns(generation, query, sourceId)) {
      state = state.copyWith(localMatches: localMatches);
    }
  }

  Future<void> _loadPage({
    required int generation,
    required String query,
    required String sourceId,
    required int page,
    required bool append,
  }) async {
    try {
      final results = await _load(query, sourceId, page);
      if (!_owns(generation, query, sourceId)) return;
      state = state.copyWith(
        items: append ? [...state.items, ...results] : results,
        page: page,
        isLoading: false,
        hasMore: results.length >= 20,
        error: null,
      );
    } catch (error) {
      if (!_owns(generation, query, sourceId)) return;
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  bool _owns(int generation, String query, String sourceId) =>
      mounted &&
      generation == _generation &&
      state.generation == generation &&
      state.query == query &&
      state.sourceId == sourceId;

  void reset() {
    final generation = ++_generation;
    state = SearchState(generation: generation);
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}

final searchStateProvider = StateNotifierProvider<SearchNotifier, SearchState>((
  ref,
) {
  final service = ref.watch(musicSourceServiceProvider);
  return SearchNotifier(
    (query, sourceId, page) async {
      if (sourceId == 'local' || sourceId == 'favorites') {
        final library = await ref.read(localMusicLibraryProvider.future);
        await library.init();
        final sourceSongs = sourceId == 'local'
            ? library.songs
            : await ref.read(playlistServiceProvider).getAllSongs('favorites');
        final normalized = query.trim().toLowerCase();
        final matches = sourceSongs.where((song) {
          return song.name.toLowerCase().contains(normalized) ||
              song.singer.toLowerCase().contains(normalized) ||
              song.album.toLowerCase().contains(normalized);
        }).toList();
        final start = (page - 1) * 20;
        if (start >= matches.length) return const [];
        return matches.skip(start).take(20).toList();
      }
      return service.search(
        query,
        customSourceId: sourceId,
        page: page,
        type: 'music',
      );
    },
    () => ref.read(selectedSourceIdProvider),
    loadLocalMatches: _loadLocalMusicMatches(ref),
  );
});

/// 本地补充结果：按标题、歌手或专辑模糊匹配。
LocalMatchLoader _loadLocalMusicMatches(Ref ref) {
  return (String query, int limit) async {
    try {
      final library = await ref.read(localMusicLibraryProvider.future);
      await library.init();
      final normalized = query.toLowerCase();
      final matches = library.songs
          .where((song) {
            return song.name.toLowerCase().contains(normalized) ||
                song.singer.toLowerCase().contains(normalized) ||
                song.album.toLowerCase().contains(normalized);
          })
          .take(limit)
          .toList();
      return matches;
    } catch (error) {
      return const [];
    }
  };
}

// 搜索历史记录（持久化）
final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
      return SearchHistoryNotifier();
    });

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance),
      super([]) {
    _load();
  }

  final StorageLoader _storage;
  int _generation = 0;

  Future<void> _load() async {
    final generation = _generation;
    try {
      final storage = await _storage();
      final value = storage.getStringList('search_history');
      if (generation == _generation) state = value;
    } catch (_) {}
  }

  Future<void> add(String keyword) async {
    if (keyword.trim().isEmpty) return;
    ++_generation;
    final previous = state;
    final updated = [keyword, ...state.where((s) => s != keyword)];
    if (updated.length > 20) updated.removeRange(20, updated.length);
    state = updated;
    try {
      await (await _storage()).setStringList('search_history', updated);
    } catch (_) {
      if (identical(state, updated) || state == updated) state = previous;
      rethrow;
    }
  }

  Future<void> remove(String keyword) async {
    ++_generation;
    final previous = state;
    final updated = state.where((s) => s != keyword).toList();
    state = updated;
    try {
      await (await _storage()).setStringList('search_history', updated);
    } catch (_) {
      if (identical(state, updated) || state == updated) state = previous;
      rethrow;
    }
  }

  Future<void> clear() async {
    ++_generation;
    final previous = state;
    const updated = <String>[];
    state = updated;
    try {
      await (await _storage()).setStringList('search_history', updated);
    } catch (_) {
      if (state.isEmpty) state = previous;
      rethrow;
    }
  }

  Future<void> replaceAll(List<String> values) async {
    final normalized = <String>[];
    for (final value in values) {
      final keyword = value.trim();
      if (keyword.isEmpty || normalized.contains(keyword)) continue;
      normalized.add(keyword);
      if (normalized.length == 20) break;
    }
    ++_generation;
    final previous = state;
    state = normalized;
    try {
      await (await _storage()).setStringList('search_history', normalized);
    } catch (_) {
      if (identical(state, normalized) || state == normalized) state = previous;
      rethrow;
    }
  }

  void applyCommitted(List<String> value) {
    ++_generation;
    state = value;
  }
}

// 热搜词（从酷我获取）
final hotSearchProvider = FutureProvider<List<String>>((ref) async {
  final musicSourceService = ref.watch(musicSourceServiceProvider);
  final builtIn = musicSourceService.builtInSources;
  final kwSource = builtIn.get('kw');
  if (kwSource == null) return _defaultHotSearch;
  try {
    final dio = kwSource.createDioForService();
    final response = await dio.get(
      'https://search.kuwo.cn/r.s',
      queryParameters: {
        'client': 'kt',
        'rn': '20',
        'pn': '0',
        'type': 'bang',
        'data': 'content',
        'show_copyright_off': '0',
        'isbang': '1',
        'bangid': '93',
      },
    );
    final data = response.data;
    if (data is Map) {
      final list = data['musiclist'] as List?;
      if (list != null) {
        return list
            .take(20)
            .map((item) => (item as Map)['SONGNAME'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
  } catch (_) {}
  return _defaultHotSearch;
});

const _defaultHotSearch = [
  '周杰伦',
  '薛之谦',
  '陈奕迅',
  '林俊杰',
  '邓紫棋',
  '毛不易',
  '华晨宇',
  '李荣浩',
  '周深',
  '张杰',
];
