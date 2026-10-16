import 'package:shared_preferences/shared_preferences.dart';

final class SyncCursorStore {
  SyncCursorStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _key = 'sync_server_cursor_v1';
  final Future<SharedPreferences> Function() _preferences;

  Future<int> read() async => (await _preferences()).getInt(_key) ?? 0;

  Future<void> write(int cursor) async {
    if (cursor < 0) throw ArgumentError.value(cursor, 'cursor');
    final ok = await (await _preferences()).setInt(_key, cursor);
    if (!ok) throw StateError('Unable to persist sync cursor');
  }

  Future<void> clear() async => (await _preferences()).remove(_key);
}
