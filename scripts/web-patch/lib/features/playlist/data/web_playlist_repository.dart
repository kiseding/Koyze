// Web 版歌单仓库：复用 PlaylistSnapshotCodec，落盘改走 SharedPreferences
// （浏览器里是 localStorage）。原生版的 FilePlaylistRepository 用 dart:io，
// 在 Web 上运行时会抛 UnsupportedError。

import 'package:shared_preferences/shared_preferences.dart';

import 'playlist_repository.dart';

class WebPlaylistRepository implements PlaylistRepository {
  WebPlaylistRepository({required SharedPreferences preferences})
    : _preferences = preferences;

  static const _storageKey = 'web_playlists_v1';

  final SharedPreferences _preferences;
  final PlaylistSnapshotCodec _codec = const PlaylistSnapshotCodec();

  @override
  Future<PlaylistSnapshot> load() async {
    final raw = _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return PlaylistSnapshot(schemaVersion: 1, playlists: const []);
    }
    try {
      return _codec.decode(raw);
    } catch (_) {
      // 损坏的缓存不该让整个应用起不来。
      return PlaylistSnapshot(schemaVersion: 1, playlists: const []);
    }
  }

  @override
  Future<void> save(PlaylistSnapshot snapshot) async {
    await _preferences.setString(_storageKey, _codec.encode(snapshot));
  }
}
