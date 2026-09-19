import '../../../core/storage/storage_service.dart';
import '../../player/domain/music_item.dart';

/// 在线刮削身份：本地文件按 path，NAS / Subsonic 按 [MusicItem.identityKey]。
///
/// overlay 只叠封面、歌词和空缺的歌名/歌手/专辑，**不改**
/// `source` / `platform` / `id` / `songmid`。本地库要改播放身份时
/// 自己读 [identityOf]，不要走 overlay。
class MusicScrapeStore {
  MusicScrapeStore({required StorageService storage}) : _storage = storage;

  static const storageKey = 'music_scrape_v1';
  static const legacyLocalKey = 'local_music_scrape_v1';
  static const legacyNasKey = 'nas_music_scrape_v1';

  final StorageService _storage;
  final Map<String, Map<String, dynamic>> _identities = {};
  bool _loaded = false;
  bool _hadLegacy = false;
  bool _dirty = false;

  int get length => _identities.length;

  Map<String, dynamic>? identityOf(String key) {
    final value = _identities[key];
    return value == null ? null : Map<String, dynamic>.unmodifiable(value);
  }

  Future<void> init() async {
    if (_loaded) return;
    _load();
    _loaded = true;
    if (_hadLegacy) {
      await _persist();
      await _storage.remove(legacyLocalKey);
      await _storage.remove(legacyNasKey);
      _hadLegacy = false;
    }
  }

  void _load() {
    _identities.clear();
    _hadLegacy = false;
    _ingest(legacyLocalKey, legacy: true);
    _ingest(legacyNasKey, legacy: true);
    _ingest(storageKey, legacy: false);
  }

  void _ingest(String key, {required bool legacy}) {
    final entries = _storage.getJsonList(key);
    if (legacy && entries.isNotEmpty) _hadLegacy = true;
    for (final entry in entries) {
      final storedKey = _keyOf(entry);
      if (storedKey.isEmpty) continue;
      _identities[storedKey] = Map<String, dynamic>.from(entry)
        ..remove('key')
        ..remove('path');
    }
  }

  static String _keyOf(Map<String, dynamic> entry) {
    final key = entry['key']?.toString().trim() ?? '';
    if (key.isNotEmpty) return key;
    return entry['path']?.toString().trim() ?? '';
  }

  Future<void> save(String key, Map<String, dynamic> identity) async {
    await init();
    if (key.isEmpty) return;
    _identities[key] = Map<String, dynamic>.from(identity)
      ..remove('key')
      ..remove('path');
    await _persist();
  }

  void discard(String key) {
    if (_identities.remove(key) != null) _dirty = true;
  }

  void discardWhere(bool Function(String key) test) {
    final keys = _identities.keys.where(test).toList(growable: false);
    for (final key in keys) {
      _identities.remove(key);
      _dirty = true;
    }
  }

  Future<void> flush() async {
    await init();
    if (!_dirty) return;
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.setJsonList(
      storageKey,
      _identities.entries
          .map((entry) => {'key': entry.key, ...entry.value})
          .toList(),
    );
    _dirty = false;
  }

  List<MusicItem> overlayAll(List<MusicItem> songs) {
    return songs.map(overlay).toList(growable: false);
  }

  MusicItem overlay(MusicItem song) {
    final identity = _identities[song.identityKey];
    if (identity == null) return song;
    final scrapedArtwork = _nonEmpty(identity['artwork']);
    final lyrics = _nonEmpty(identity['lyrics']);
    final lyricsUrl = _nonEmpty(identity['lyricsUrl']);
    final scrapedName = _nonEmpty(identity['name']);
    final scrapedSinger = _nonEmpty(identity['singer']);
    final scrapedAlbum = _nonEmpty(identity['album']);
    final meta = <String, dynamic>{
      ...?song.meta,
      if (lyrics != null) 'localLyrics': lyrics,
      if (_nonEmpty(identity['platform']) != null)
        'scrapedPlatform': identity['platform'],
      if (_nonEmpty(identity['songmid']) != null)
        'scrapedSongmid': identity['songmid'],
    };
    return song.copyWith(
      name: song.name.trim().isNotEmpty ? song.name : (scrapedName ?? song.name),
      singer: song.singer.trim().isNotEmpty
          ? song.singer
          : (scrapedSinger ?? song.singer),
      album: song.album.trim().isNotEmpty
          ? song.album
          : (scrapedAlbum ?? song.album),
      artwork: scrapedArtwork ?? song.artwork,
      lyricsUrl: lyricsUrl ?? song.lyricsUrl,
      meta: meta,
    );
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
