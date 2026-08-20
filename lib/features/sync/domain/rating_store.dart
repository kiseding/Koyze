import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class RatingStore {
  RatingStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _key = 'sync_ratings_v1';
  final Future<SharedPreferences> Function() _preferences;

  Future<Map<String, int>> load() async {
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
    final values = await load()
      ..remove(songId);
    await (await _preferences()).setString(_key, jsonEncode(values));
  }

  Future<void> applyRemote(String songId, int rating) async {
    final values = await load();
    values[songId] = rating;
    await (await _preferences()).setString(_key, jsonEncode(values));
  }

  Future<void> applyRemoteRemove(String songId) => remove(songId);

  Future<void> clear() async => (await _preferences()).remove(_key);
}
