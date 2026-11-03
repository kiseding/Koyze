import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../player/domain/music_item.dart';

/// 一次落盘的库快照。
class NasLibrarySnapshot {
  const NasLibrarySnapshot({required this.songs, required this.savedAt});

  final List<MusicItem> songs;
  final DateTime savedAt;

  Duration get age => DateTime.now().difference(savedAt);
}

/// 把 NAS 曲库按服务器存一份到本地，避免每次进页面都整库重扫；
/// 服务器不可达时也能先把上次的列表显示出来。
class NasLibraryCache {
  NasLibraryCache({
    required this.serverId,
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? _defaultDirectory;

  static const _version = 1;

  final String serverId;
  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/nas_library');
  }

  String get _fileName {
    final safe = serverId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return '$safe.json';
  }

  Future<File> _file() async {
    final dir = await _directory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_fileName');
  }

  Future<NasLibrarySnapshot?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['version'] != _version) return null;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        (decoded['savedAt'] as num?)?.toInt() ?? 0,
      );
      final songs = <MusicItem>[];
      for (final item in (decoded['songs'] as List? ?? const [])) {
        if (item is! Map) continue;
        try {
          songs.add(MusicItem.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // 单条脏数据不该毁掉整份缓存。
        }
      }
      if (songs.isEmpty) return null;
      return NasLibrarySnapshot(songs: songs, savedAt: savedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(List<MusicItem> songs) async {
    if (songs.isEmpty) return;
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'version': _version,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'songs': songs.map((song) => song.toJson()).toList(growable: false),
        }),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (_) {
      // 缓存失败不影响正常使用。
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // ignore
    }
  }
}
