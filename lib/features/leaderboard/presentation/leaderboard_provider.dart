import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/music_source/platform/music_platform.dart';
import '../../../core/music_source/platform/built_in_source_manager.dart';
import '../../../core/storage/storage_service.dart';
import '../../search/presentation/search_provider.dart';
import '../../player/domain/music_item.dart';

final builtInSourcesProvider = Provider<BuiltInSourceManager>((ref) {
  final musicSourceService = ref.watch(musicSourceServiceProvider);
  return musicSourceService.builtInSources;
});

// 排行榜分类列表：磁盘缓存优先（冷启动直接渲染上次的榜单），
// 后台拉取最新覆盖并落盘；失败且无缓存才进入错误态。
final leaderboardCategoriesProvider =
    StateNotifierProvider<
      LeaderboardCategoriesNotifier,
      AsyncValue<List<LeaderboardCategory>>
    >((ref) {
      return LeaderboardCategoriesNotifier(
        ref,
        () => StorageService.instance,
      );
    });

class LeaderboardCategoriesNotifier
    extends StateNotifier<AsyncValue<List<LeaderboardCategory>>> {
  LeaderboardCategoriesNotifier(this._ref, [StorageLoader? storage])
    : _storage = storage ?? (() => StorageService.instance),
      super(const AsyncValue.loading()) {
    _init();
  }

  static const _cacheKey = 'leaderboard_categories_cache_v1';

  final Ref _ref;
  final StorageLoader _storage;
  bool _refreshing = false;

  Future<void> _init() async {
    final cached = await _loadCache();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      state = AsyncValue.data(cached);
      _refresh();
    } else {
      await _refresh();
    }
  }

  /// 拉取最新榜单：成功覆盖状态并落盘；失败时若已有缓存则静默保留。
  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final builtIn = _ref.read(builtInSourcesProvider);
      final fresh = await builtIn.getAllLeaderboardCategories();
      if (!mounted) return;
      state = AsyncValue.data(fresh);
      _persist(fresh);
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (state is! AsyncData) {
        state = AsyncValue.error(error, stackTrace);
      }
    } finally {
      _refreshing = false;
    }
  }

  /// 手动刷新入口（重试按钮 / 刷新按钮经 invalidate 重建也可）。
  Future<void> refresh() => _refresh();

  Future<List<LeaderboardCategory>> _loadCache() async {
    try {
      final storage = await _storage();
      final raw = storage.getJsonList(_cacheKey);
      final list = <LeaderboardCategory>[];
      for (final item in raw) {
        final id = item['id']?.toString();
        final name = item['name']?.toString();
        if (id == null || id.isEmpty || name == null) continue;
        list.add(
          LeaderboardCategory(
            id: id,
            name: name,
            platform: item['platform']?.toString(),
            coverUrl: item['coverUrl']?.toString(),
          ),
        );
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<LeaderboardCategory> categories) async {
    try {
      final storage = await _storage();
      await storage.setJsonList(_cacheKey, [
        for (final c in categories)
          {
            'id': c.id,
            'name': c.name,
            'platform': c.platform,
            'coverUrl': c.coverUrl,
          },
      ]);
    } catch (_) {}
  }
}

/// 布局项：平台或具体榜单。
/// - [platform] 为 `platform:<id>`
/// - 榜单为 `category:<platform>:<id>`（与 LeaderboardCategory.id 一致）
class LeaderboardLayoutItem {
  const LeaderboardLayoutItem({required this.key, required this.hidden});

  final String key;
  final bool hidden;

  static const platformPrefix = 'platform:';
  static const categoryPrefix = 'category:';

  bool get isPlatform => key.startsWith(platformPrefix);
  bool get isCategory => key.startsWith(categoryPrefix);

  String? get platformId =>
      isPlatform ? key.substring(platformPrefix.length) : null;

  String? get categoryId =>
      isCategory ? key.substring(categoryPrefix.length) : null;

  LeaderboardLayoutItem copyWith({bool? hidden}) {
    return LeaderboardLayoutItem(key: key, hidden: hidden ?? this.hidden);
  }

  Map<String, dynamic> toJson() => {'key': key, 'hidden': hidden};

  factory LeaderboardLayoutItem.fromJson(Map<String, dynamic> json) {
    return LeaderboardLayoutItem(
      key: json['key']?.toString() ?? '',
      hidden: json['hidden'] == true,
    );
  }
}

/// 榜单页布局：平台与榜单的固定平台顺序及显隐。
final leaderboardLayoutProvider =
    StateNotifierProvider<
      LeaderboardLayoutNotifier,
      List<LeaderboardLayoutItem>
    >((ref) {
      return LeaderboardLayoutNotifier();
    });

class LeaderboardLayoutNotifier
    extends StateNotifier<List<LeaderboardLayoutItem>> {
  static const _key = 'leaderboard_layout_v1';
  static const _orderVersionKey = 'leaderboard_layout_order_version';
  static const _orderVersion = 2;
  static const defaultPlatformOrder = ['tx', 'kw', 'wy'];

  LeaderboardLayoutNotifier({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance),
      super(const []) {
    _load();
  }

  final StorageLoader _storage;
  int _generation = 0;
  bool _needsOrderMigration = false;

  Future<void> _load() async {
    final generation = _generation;
    try {
      final storage = await _storage();
      final raw = storage.getJsonList(_key);
      _needsOrderMigration =
          (storage.getInt(_orderVersionKey) ?? 1) < _orderVersion;
      if (generation == _generation && raw.isNotEmpty) {
        state = raw
            .map(LeaderboardLayoutItem.fromJson)
            .where((item) => item.key.isNotEmpty)
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final generation = ++_generation;
    try {
      await (await _storage()).setJsonList(
        _key,
        state.map((item) => item.toJson()).toList(),
      );
      await (await _storage()).setInt(_orderVersionKey, _orderVersion);
    } catch (_) {
      if (generation == _generation) {}
    }
  }

  /// 用最新分类生成默认布局（仅当尚无布局时）。
  void ensureDefaultLayout(List<LeaderboardCategory> categories) {
    if (state.isNotEmpty) {
      _migrateOldDefaultOrder();
      return;
    }
    const platformOrder = defaultPlatformOrder;
    final items = <LeaderboardLayoutItem>[];
    for (final platform in platformOrder) {
      final platformCategories = categories
          .where((c) => c.platform == platform)
          .toList();
      if (platformCategories.isEmpty) continue;
      items.add(
        LeaderboardLayoutItem(key: 'platform:$platform', hidden: false),
      );
      for (final category in platformCategories) {
        items.add(
          LeaderboardLayoutItem(key: 'category:${category.id}', hidden: false),
        );
      }
    }
    for (final platform in {
      for (final c in categories) c.platform,
    }.where((p) => p != null && !platformOrder.contains(p))) {
      items.add(
        LeaderboardLayoutItem(key: 'platform:$platform', hidden: false),
      );
    }
    state = items;
    _persist();
  }

  void _migrateOldDefaultOrder() {
    if (!_needsOrderMigration) return;
    _needsOrderMigration = false;
    final platforms = state
        .where((item) => item.isPlatform)
        .map((item) => item.platformId)
        .whereType<String>()
        .toList();
    // Only migrate the shipped legacy order. Custom platform orders remain
    // untouched; category order and hidden flags within each block are kept.
    if (platforms.length < 2 || platforms[0] != 'kw' || platforms[1] != 'tx') {
      _persist();
      return;
    }
    final blocks = <String, List<LeaderboardLayoutItem>>{};
    String? currentPlatform;
    for (final item in state) {
      if (item.isPlatform) currentPlatform = item.platformId;
      if (currentPlatform != null) {
        blocks.putIfAbsent(currentPlatform, () => []).add(item);
      }
    }
    final reordered = <LeaderboardLayoutItem>[];
    for (final platform in defaultPlatformOrder) {
      reordered.addAll(blocks.remove(platform) ?? const []);
    }
    for (final block in blocks.values) {
      reordered.addAll(block);
    }
    if (reordered.length == state.length) state = reordered;
    _persist();
  }

  /// 隐藏平台：隐藏平台头及其全部榜单。
  void hidePlatform(String platformId) {
    _setHidden(
      (item) =>
          item.isPlatform && item.platformId == platformId ||
          item.isCategory &&
              item.categoryId?.startsWith('$platformId:') == true,
      true,
    );
  }

  void hideCategory(String categoryId) {
    _setHidden((item) => item.key == 'category:$categoryId', true);
  }

  void restoreItem(String key) {
    _setHidden((item) => item.key == key, false);
  }

  void restoreAll() {
    state = [for (final item in state) item.copyWith(hidden: false)];
    _persist();
  }

  void _setHidden(bool Function(LeaderboardLayoutItem) match, bool hidden) {
    var changed = false;
    state = [
      for (final item in state)
        if (match(item) && item.hidden != hidden)
          (changed = true, item.copyWith(hidden: hidden)).$2
        else
          item,
    ];
    if (changed) _persist();
  }
}

// 排行榜歌曲
final leaderboardSongsProvider = FutureProvider.family<List<MusicItem>, String>(
  (ref, leaderboardId) async {
    final builtIn = ref.watch(builtInSourcesProvider);
    // 从 categoryId 中提取平台信息
    // 格式: "platform:id"，如 "kw:93"
    final parts = leaderboardId.split(':');
    if (parts.length != 2) return [];
    final platformId = parts[0];
    final id = parts[1];
    return builtIn.getLeaderboardSongs(platformId, id);
  },
);
