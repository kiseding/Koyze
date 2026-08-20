/// In-memory entries with a last-access TTL. Disk helpers live beside loaders.
class TtlCacheEntry<T> {
  TtlCacheEntry(this.value, this.lastAccessedAt);

  final T value;
  DateTime lastAccessedAt;
}

class TtlCache<T> {
  TtlCache({required this.ttl, DateTime Function()? clock, this.maxEntries})
    : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;

  /// 可选条目数上限：超出时淘汰最久未访问的条目，防止长会话内存膨胀。
  final int? maxEntries;
  final Map<String, TtlCacheEntry<T>> _entries = {};

  static const defaultTtl = Duration(hours: 12);

  T? get(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    final now = _clock();
    if (now.difference(entry.lastAccessedAt) > ttl) {
      _entries.remove(key);
      return null;
    }
    entry.lastAccessedAt = now;
    return entry.value;
  }

  void set(String key, T value) {
    _entries[key] = TtlCacheEntry(value, _clock());
    final limit = maxEntries;
    if (limit != null && _entries.length > limit) {
      _evictLeastRecentlyUsed(limit);
    }
  }

  void _evictLeastRecentlyUsed(int keep) {
    // 淘汰最久未访问，直到回到上限内。
    final sorted = _entries.entries.toList()
      ..sort(
        (a, b) => a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt),
      );
    final excess = sorted.length - keep;
    for (var i = 0; i < excess; i++) {
      _entries.remove(sorted[i].key);
    }
  }

  void remove(String key) => _entries.remove(key);

  void clear() => _entries.clear();

  int get length => _entries.length;
}
