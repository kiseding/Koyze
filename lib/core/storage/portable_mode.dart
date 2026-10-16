import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Windows portable mode is enabled by placing `portable.flag` beside Koyze.exe.
final class PortableMode {
  PortableMode._();

  static String? get root {
    if (!Platform.isWindows) return null;
    final executable = File(Platform.resolvedExecutable);
    final directory = executable.parent;
    if (!File(
      '${directory.path}${Platform.pathSeparator}portable.flag',
    ).existsSync()) {
      return null;
    }
    return '${directory.path}${Platform.pathSeparator}portable_data';
  }

  static Future<void> initialize() async {
    final path = root;
    if (path != null) await Directory(path).create(recursive: true);
  }
}

/// SharedPreferences-compatible JSON store used only in portable mode.
final class PortablePreferencesStore extends SharedPreferencesStorePlatform {
  PortablePreferencesStore(this.path);

  final String path;
  Map<String, Object> _data = <String, Object>{};
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final file = File(path);
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        _data = decoded.map<String, Object>(
          (key, value) => MapEntry(key.toString(), value as Object),
        );
      }
    } catch (_) {
      _data = <String, Object>{};
    }
  }

  Future<bool> _save() async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(jsonEncode(_data), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    await _load();
    _data.remove(key);
    return _save();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await _load();
    _data[key] = value;
    return _save();
  }

  @override
  Future<bool> clear() async {
    await _load();
    _data.removeWhere((key, _) => key.startsWith('flutter.'));
    return _save();
  }

  @override
  Future<Map<String, Object>> getAll() async {
    await _load();
    return Map<String, Object>.from(_data);
  }
}
