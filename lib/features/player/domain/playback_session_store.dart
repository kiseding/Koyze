import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/storage/storage_service.dart';
import 'music_item.dart';
import 'playback_session.dart';

/// 播放会话的本地持久化，供下次启动时恢复上次播放状态。
class PlaybackSessionStore {
  PlaybackSessionStore(this._load);

  static const _legacyKey = 'playback_session_v1';
  static const _contextKey = 'playback_session_context_v2';
  static const _currentKey = 'playback_session_current_v2';

  final StorageLoader _load;
  String? _lastContextJson;
  Future<void> _pendingWrite = Future<void>.value();

  Future<PlaybackSession?> load() async {
    try {
      final storage = await _load();
      final context = storage.getJson(_contextKey);
      final current = storage.getJson(_currentKey);
      if (context != null && current != null) {
        final contextJson = jsonEncode(context);
        _lastContextJson = contextJson;
        if (current['contextHash'] == _contextHash(contextJson)) {
          final session = _sanitizeSession(
            PlaybackSession.fromJson({...context, ...current}),
          );
          await _saveNow(session);
          return session;
        }
        final session = _sanitizeSession(PlaybackSession.fromJson(current));
        await _saveNow(session);
        return session;
      }

      final legacy = storage.getJson(_legacyKey);
      if (legacy == null) return null;
      final session = _sanitizeSession(PlaybackSession.fromJson(legacy));
      await _saveNow(session);
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PlaybackSession session) async {
    final write = _pendingWrite.then((_) => _saveNow(session));
    _pendingWrite = write;
    await write;
  }

  Future<void> _saveNow(PlaybackSession session) async {
    try {
      final storage = await _load();
      final context = <String, dynamic>{
        'playlistId': session.playlistId,
        'queue': [for (final item in session.queue) _durableMusicJson(item)],
      };
      final contextJson = jsonEncode(context);
      if (contextJson != _lastContextJson) {
        await storage.setString(_contextKey, contextJson);
        _lastContextJson = contextJson;
      }
      await storage.setJson(_currentKey, {
        'contextHash': _contextHash(contextJson),
        'startIndex': session.startIndex,
        'song': _durableMusicJson(session.song),
      });
      if (storage.getString(_legacyKey) != null) {
        await storage.remove(_legacyKey);
      }
    } catch (_) {}
  }

  String _contextHash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  Map<String, dynamic> _durableMusicJson(dynamic item) {
    final json = Map<String, dynamic>.from(item.toJson() as Map);
    json
      ..remove('url')
      ..remove('lyricsUrl');
    final meta = json['meta'];
    if (meta is Map) {
      json['meta'] = _sanitizeMetadata(Map<String, dynamic>.from(meta));
    }
    return json;
  }

  PlaybackSession _sanitizeSession(PlaybackSession session) {
    MusicItem sanitize(MusicItem item) =>
        MusicItem.fromJson(_durableMusicJson(item));
    return PlaybackSession(
      playlistId: session.playlistId,
      startIndex: session.startIndex,
      song: sanitize(session.song),
      queue: [for (final item in session.queue) sanitize(item)],
    );
  }

  Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> value) {
    final sanitized = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'url' ||
          key.endsWith('url') ||
          key.contains('token') ||
          key.contains('signature') ||
          key.contains('authorization') ||
          key.contains('cookie') ||
          key.contains('api_key') ||
          key.contains('apikey')) {
        continue;
      }
      final item = entry.value;
      if (item is Map) {
        sanitized[entry.key] = _sanitizeMetadata(
          Map<String, dynamic>.from(item),
        );
      } else if (item is List) {
        sanitized[entry.key] = [
          for (final nested in item)
            if (nested is Map)
              _sanitizeMetadata(Map<String, dynamic>.from(nested))
            else
              nested,
        ];
      } else {
        sanitized[entry.key] = item;
      }
    }
    return sanitized;
  }

  Future<void> clear() async {
    try {
      await _pendingWrite;
      final storage = await _load();
      await storage.remove(_legacyKey);
      await storage.remove(_contextKey);
      await storage.remove(_currentKey);
      _lastContextJson = null;
    } catch (_) {}
  }
}
