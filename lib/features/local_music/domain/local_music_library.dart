import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/player/domain/music_item.dart';

import 'local_music_scanner.dart';
import 'security_scoped_directory.dart';

/// 持久化的本地音乐索引：目录 → 文件列表 → 元数据。
/// 与 PlaylistService 的 `local` 系统歌单解耦：这里保存扫描索引与
/// 刮削身份（songmid/hash），歌曲本体写入 `local` 歌单。
class LocalMusicLibrary {
  LocalMusicLibrary({
    required StorageService storage,
    LocalMusicScanner? scanner,
  }) : _storage = storage,
       _scanner = scanner ?? LocalMusicScanner();

  static const _indexKey = 'local_music_index_v1';
  static const _dirsKey = 'local_music_dirs_v1';
  static const _downloadDirKey = 'local_music_download_dir_v1';

  final StorageService _storage;
  final LocalMusicScanner _scanner;

  /// 内嵌封面缓存目录（懒加载）。
  Future<Directory>? _artworkDir;

  /// path → 已解析元数据（刮削前）。
  final Map<String, Map<String, dynamic>> _files = {};

  /// 已配置的扫描目录。
  List<String> _directories = [];

  /// 下载目录（自动纳入扫描，不可手动移除；null 表示未配置）。
  String? _downloadDirectory;

  /// 文件路径 → 刮削到的在线身份。
  final Map<String, Map<String, dynamic>> _scrapedIdentity = {};

  bool _initialized = false;

  List<String> get directories => List.unmodifiable(_directories);
  String? get downloadDirectory => _downloadDirectory;
  int get fileCount => _files.length;

  Map<String, Map<String, dynamic>> get files => Map.unmodifiable(_files);

  Map<String, dynamic>? scrapedIdentity(String path) =>
      _scrapedIdentity[path] == null
      ? null
      : Map<String, dynamic>.unmodifiable(_scrapedIdentity[path]!);

  /// 解析出的全部本地歌曲（含刮削身份）。
  List<MusicItem> get songs => _files.values.map(_toMusicItem).toList();

  Future<void> init() async {
    if (_initialized) return;
    _directories = _storage.getStringList(_dirsKey);
    _downloadDirectory = _storage.getString(_downloadDirKey);
    _loadIndex();
    _loadScrapedIdentity();
    await SecurityScopedDirectory.restore();
    await _pruneMissingFiles();
    _initialized = true;
  }

  /// 设置下载目录为自动扫描目录（覆盖旧值并触发一次重扫）。
  Future<int> setDownloadDirectory(String directoryPath) async {
    _downloadDirectory = directoryPath;
    await _storage.setString(_downloadDirKey, directoryPath);
    _directories = _directories
        .where((dir) => dir != directoryPath)
        .toList(growable: false);
    await _persistDirectories();
    return addDirectory(directoryPath);
  }

  void _loadIndex() {
    _files.clear();
    for (final entry in _storage.getJsonList(_indexKey)) {
      final path = entry['path']?.toString();
      if (path != null && path.isNotEmpty) {
        _files[path] = Map<String, dynamic>.from(entry);
      }
    }
  }

  void _loadScrapedIdentity() {
    _scrapedIdentity.clear();
    for (final entry in _storage.getJsonList('local_music_scrape_v1')) {
      final path = entry['path']?.toString();
      if (path != null && path.isNotEmpty) {
        _scrapedIdentity[path] = Map<String, dynamic>.from(entry);
      }
    }
  }

  Future<void> _persistIndex() async {
    await _storage.setJsonList(
      _indexKey,
      _files.values.map((entry) => Map<String, dynamic>.from(entry)).toList(),
    );
  }

  Future<void> _persistDirectories() async {
    await _storage.setStringList(_dirsKey, _directories);
  }

  /// 启动时校验文件是否存在，移除失效条目。
  Future<void> _pruneMissingFiles() async {
    final missing = <String>[];
    for (final path in _files.keys) {
      if (!await File(path).exists()) missing.add(path);
    }
    if (missing.isEmpty) return;
    for (final path in missing) {
      _files.remove(path);
      _scrapedIdentity.remove(path);
    }
    await _persistIndex();
  }

  /// 添加扫描目录并增量扫描。
  Future<int> addDirectory(
    String directoryPath, {
    void Function(int scanned, int total)? onProgress,
  }) async {
    if (!_directories.contains(directoryPath)) {
      _directories = [..._directories, directoryPath];
      await _persistDirectories();
    }
    final tracks = await _scanner.scanDirectory(
      directoryPath,
      shouldSkip: (path) {
        final entry = _files[path];
        if (entry == null) return false;
        final identity = _scrapedIdentity[path];
        // 歌词和封面分别刮削；不能因为已有歌词就跳过缺封面的文件。
        return identity?['lyrics']?.toString().isNotEmpty == true &&
            identity?['artwork']?.toString().isNotEmpty == true;
      },
      onProgress: onProgress,
    );
    for (final track in tracks) {
      String? artworkPath = _files[track.path]?['artwork']?.toString();
      final embedded = track.embeddedArtwork;
      if (embedded != null && embedded.isNotEmpty) {
        artworkPath = await _persistEmbeddedArtwork(track.path, embedded);
      }
      _files[track.path] = {
        'path': track.path,
        'fileName': track.fileName,
        'extension': track.extension,
        'size': track.size,
        'modifiedAt': track.modifiedAt.toIso8601String(),
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'hasEmbeddedTags': track.hasEmbeddedTags,
        'hasEmbeddedArtwork': track.hasEmbeddedArtwork,
        'duration': track.duration.inSeconds,
        if (track.bitrate != null) 'bitrate': track.bitrate,
        if (artworkPath != null) 'artwork': artworkPath,
      };
    }
    await _persistIndex();
    return tracks.length;
  }

  Future<String> _persistEmbeddedArtwork(
    String trackPath,
    Uint8List bytes,
  ) async {
    final dir = await (_artworkDir ??= _createArtworkDir());
    final hash = sha1.convert(utf8.encode(trackPath)).toString();
    final file = File('${dir.path}/$hash.jpg');
    if (await file.exists()) return file.path;
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Directory> _createArtworkDir() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/local_artwork');
    await dir.create(recursive: true);
    return dir;
  }

  /// 重新扫描全部目录（用于显式刷新），含下载目录。
  Future<int> rescanAll({
    void Function(int scanned, int total)? onProgress,
  }) async {
    var added = 0;
    final downloadDir = _downloadDirectory;
    if (downloadDir != null && !_directories.contains(downloadDir)) {
      added += await addDirectory(downloadDir, onProgress: onProgress);
    }
    for (final directoryPath in List.of(_directories)) {
      added += await addDirectory(directoryPath, onProgress: onProgress);
    }
    return added;
  }

  /// 仅重新扫描下载目录（下载完成后调用，增量更新）。
  Future<int> rescanDownloadDirectory() async {
    final downloadDir = _downloadDirectory;
    if (downloadDir == null) return 0;
    return addDirectory(downloadDir);
  }

  /// 将已完成下载任务的元数据写入本地索引。
  /// 部分平台下载文件没有内嵌 tag，扫描器无法从文件本身建立条目，
  /// 这时使用下载任务保存的在线元数据作为可靠回退。
  Future<void> upsertDownloadedSong({
    required String path,
    required String title,
    required String artist,
    required String album,
    required String source,
    required String platform,
    String? songmid,
    String? hash,
    String? artwork,
    int? duration,
  }) async {
    final file = File(path);
    if (!await file.exists()) return;
    final stat = await file.stat();
    final fileName = file.uri.pathSegments.last;
    final dot = fileName.lastIndexOf('.');
    final extension = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : '';
    _files[path] = {
      'path': path,
      'fileName': fileName,
      'extension': extension,
      'size': stat.size,
      'modifiedAt': stat.modified.toIso8601String(),
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration ?? 0,
      'hasEmbeddedTags': false,
      if (artwork != null && artwork.isNotEmpty) 'artwork': artwork,
    };
    _scrapedIdentity[path] = {
      'platform': platform,
      'source': source,
      if (songmid != null && songmid.isNotEmpty) 'songmid': songmid,
      if (hash != null && hash.isNotEmpty) 'hash': hash,
      'name': title,
      'singer': artist,
      'album': album,
      if (artwork != null && artwork.isNotEmpty) 'artwork': artwork,
    };
    await Future.wait([_persistIndex(), _persistScrapedIdentity()]);
  }

  /// 移除目录及其索引（下载目录不可移除）。
  Future<void> removeDirectory(String directoryPath) async {
    if (directoryPath == _downloadDirectory) return;
    _directories = _directories
        .where((dir) => dir != directoryPath)
        .toList(growable: false);
    final prefix = directoryPath.endsWith('/')
        ? directoryPath
        : '$directoryPath/';
    _files.removeWhere((path, _) => path.startsWith(prefix));
    _scrapedIdentity.removeWhere((path, _) => path.startsWith(prefix));
    await Future.wait([_persistDirectories(), _persistIndex()]);
  }

  /// 记录刮削到的在线身份（songmid/hash/artwork/lyricsUrl 等）。
  Future<void> applyScrapedIdentity(
    String path,
    Map<String, dynamic> identity,
  ) async {
    _scrapedIdentity[path] = Map<String, dynamic>.from(identity);
    final artwork = identity['artwork']?.toString();
    final current = _files[path];
    if (current != null && artwork != null && artwork.isNotEmpty) {
      _files[path] = {...current, 'artwork': artwork};
      await Future.wait([_persistIndex(), _persistScrapedIdentity()]);
      return;
    }
    await _persistScrapedIdentity();
  }

  /// 下载完成后补充在线封面：为没有内嵌封面/刮削封面的条目写入在线 artwork，
  /// 使下载歌曲立即可见封面（不必等刮削）。
  Future<void> applyDownloadArtwork(Map<String, String> pathToArtwork) async {
    var changed = false;
    for (final entry in pathToArtwork.entries) {
      final current = _files[entry.key];
      if (current == null) continue;
      if (current['artwork']?.toString().isNotEmpty == true) continue;
      final identity = _scrapedIdentity[entry.key];
      if (identity?['artwork']?.toString().isNotEmpty == true) continue;
      _files[entry.key] = {...current, 'artwork': entry.value};
      changed = true;
    }
    if (changed) await _persistIndex();
  }

  Future<void> _persistScrapedIdentity() async {
    await _storage.setJsonList(
      'local_music_scrape_v1',
      _scrapedIdentity.entries
          .map((entry) => {'path': entry.key, ...entry.value})
          .toList(),
    );
  }

  /// 将索引中的本地文件转为 MusicItem（双身份：本地 filePath + 在线 songmid/hash）。
  MusicItem _toMusicItem(Map<String, dynamic> entry) {
    final path = entry['path']!.toString();
    final fileName = entry['fileName']?.toString() ?? '';
    final identity = _scrapedIdentity[path];
    final songmid =
        identity?['songmid']?.toString() ?? entry['songmid']?.toString();
    final hash = identity?['hash']?.toString() ?? entry['hash']?.toString();
    final rawArtwork =
        identity?['artwork']?.toString() ?? entry['artwork']?.toString();
    final artwork = rawArtwork == null || rawArtwork.isEmpty
        ? null
        : (Uri.tryParse(rawArtwork)?.scheme.isNotEmpty == true
              ? rawArtwork
              : File(rawArtwork).uri.toString());
    final lyricsUrl =
        identity?['lyricsUrl']?.toString() ?? entry['lyricsUrl']?.toString();
    final localLyrics = identity?['lyrics']?.toString();

    return MusicItem(
      id: songmid != null
          ? 'local:$songmid'
          : 'local:${sha1.convert(utf8.encode(path)).toString()}',
      name:
          identity?['name']?.toString() ??
          entry['title']?.toString() ??
          titleFromFileName(fileName),
      singer:
          identity?['singer']?.toString() ??
          entry['artist']?.toString() ??
          '未知歌手',
      album: identity?['album']?.toString() ?? entry['album']?.toString() ?? '',
      duration: Duration(seconds: entry['duration'] ?? 0),
      source: 'local',
      platform: identity?['platform']?.toString() ?? 'local',
      artwork: artwork,
      // Uri.file handles Windows drive letters and iOS paths correctly.
      url: Uri.file(path).toString(),
      lyricsUrl: lyricsUrl,
      isPlayable: true,
      songmid: songmid,
      hash: hash,
      meta: {
        'filePath': path,
        'ext': entry['extension']?.toString() ?? '',
        'local': true,
        if (_localActualQuality(entry) != null)
          'localActualQuality': _localActualQuality(entry),
        if (localLyrics != null && localLyrics.isNotEmpty)
          'localLyrics': localLyrics,
      },
    );
  }

  String? _localActualQuality(Map<String, dynamic> entry) {
    final extension = entry['extension']?.toString().toLowerCase() ?? '';
    if (const {'flac', 'alac', 'ape', 'wav', 'aiff'}.contains(extension)) {
      return 'flac';
    }
    final bitrate = entry['bitrate'];
    if (bitrate is! int || bitrate <= 0) return null;
    if (bitrate >= 280000) return '320k';
    if (bitrate >= 176000) return '192k';
    return '128k';
  }
}
