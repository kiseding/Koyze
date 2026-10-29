import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_service.dart';
import '../domain/music_item.dart';

/// 最近播放过的完整曲目档案。
///
/// 播放历史只存 id 与文字（`songId` / `songTitle` / `source`），够统计用，
/// 但不足以重新播放——真正解析播放地址还需要 `songmid` / `hash` / `meta`。
/// 这里按「来源 + 原始 id」记住最近 200 首的完整 JSON，供播放历史反查。
///
/// 只存最近这么多首是刻意的：档案变旧之后歌曲本身也很可能失效，
/// 而 `songmid` 之类的字段体积极小，200 首约占 40KB。
class PlayableSongStore {
  PlayableSongStore(this._storageLoader);

  static const String storageKey = 'playable_songs_v1';
  static const int maxEntries = 200;

  final StorageLoader _storageLoader;

  /// 插入顺序即「最后播放时间」，越靠后越新。
  final Map<String, Map<String, dynamic>> _entries = {};
  StorageService? _storage;
  bool _loaded = false;

  Future<StorageService> _storageAsync() async =>
      _storage ??= await _storageLoader();

  static String keyOf(String source, String songId) =>
      '${source.trim().toLowerCase()}|$songId';

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = (await _storageAsync()).getString(storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map) {
          _entries[entry.key.toString()] = Map<String, dynamic>.from(value);
        }
      }
    } catch (_) {
      // 存档损坏就当空的重来：这只是加速用的缓存，丢了不影响任何功能。
      _entries.clear();
    }
  }

  int get length => _entries.length;

  /// 记一首歌。重复播放只更新排序，不新增条目。
  Future<void> remember(MusicItem song) async {
    if (song.id.isEmpty) return;
    final key = keyOf(song.source, song.id);
    _entries.remove(key);
    _entries[key] = song.toJson();
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    await _save();
  }

  MusicItem? byKey(String source, String songId) {
    final json = _entries[keyOf(source, songId)];
    if (json == null) return null;
    try {
      return MusicItem.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    try {
      await (await _storageAsync()).setString(
        storageKey,
        json.encode(_entries),
      );
    } catch (_) {
      // 写失败不抛出：下次播放会再试一次。
    }
  }
}

final playableSongStoreProvider = Provider<PlayableSongStore>((ref) {
  final store = PlayableSongStore(() => StorageService.instance);
  unawaited(store.load());
  return store;
});
