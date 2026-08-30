import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class RatingStore {
  RatingStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _key = 'sync_ratings_v1';
  final Future<SharedPreferences> Function() _preferences;

  Map<String, int>? _cached;
  Future<Map<String, int>>? _pending;

  /// 读取评分：首次从磁盘加载后常驻内存缓存，后续读取零开销。
  /// 手动切歌（lazy 队列 refill / shuffle 重建时逐首查 dislike）高频
  /// 走这里，每次都 jsonDecode 全量解析会让切歌明显发卡。
  Future<Map<String, int>> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    return _pending ??= _loadFromDisk().then((values) {
      _cached ??= values;
      _pending = null;
      return _cached!;
    });
  }

  Future<Map<String, int>> _loadFromDisk() async {
    final prefs = await _preferences();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): (entry.value as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> set(String songId, int rating) async {
    if (rating < 0 || rating > 5) throw ArgumentError.value(rating, 'rating');
    final values = await load();
    values[songId] = rating;
    await (await _preferences()).setString(_key, jsonEncode(values));
  }

  Future<void> remove(String songId) async {
    final values = await load()..remove(songId);
    await (await _preferences()).setString(_key, jsonEncode(values));
  }

  Future<void> applyRemote(String songId, int rating) async {
    final values = await load();
    values[songId] = rating;
    await (await _preferences()).setString(_key, jsonEncode(values));
  }

  Future<void> applyRemoteRemove(String songId) => remove(songId);

  Future<void> clear() async {
    _cached = null;
    _pending = null;
    await (await _preferences()).remove(_key);
  }
}
