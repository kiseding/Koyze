import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/player/domain/music_item.dart';

import 'android_directory_access.dart';
import 'local_music_debug_log.dart';
import 'local_music_scanner.dart';
import 'security_scoped_directory.dart';

/// 持久化的本地音乐索引：目录 → 文件列表 → 元数据。
/// 与 PlaylistService 的 `local` 系统歌单解耦：这里保存扫描索引与
/// 刮削身份（songmid/hash），歌曲本体写入 `local` 歌单。
class LocalMusicLibrary {
  // Keep the public named argument `storage` stable for tests and callers.
  LocalMusicLibrary({
    required StorageService storage,
    LocalMusicScanner? scanner,
    // ignore: prefer_initializing_formals
  }) : _storage = storage,
       _scanner = scanner ?? LocalMusicScanner();

  static const _indexKey = 'local_music_index_v1';
  static const _dirsKey = 'local_music_dirs_v1';
  static const _downloadDirKey = 'local_music_download_dir_v1';
  static const _androidMediaStoreEnabledKey =
      'local_music_android_mediastore_enabled_v1';

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
  bool get androidMediaStoreEnabled =>
      _storage.getBool(_androidMediaStoreEnabledKey) == true;
  bool get hasConfiguredSources =>
      _directories.isNotEmpty ||
      _downloadDirectory != null ||
      androidMediaStoreEnabled;
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
    LocalMusicDebugLog.info('library.init.start', 'loading local music index');
    _directories = _storage.getStringList(_dirsKey);
    _downloadDirectory = _storage.getString(_downloadDirKey);
    _loadIndex();
    _loadScrapedIdentity();
    LocalMusicDebugLog.info(
      'library.init.loaded',
      'directories=${_directories.length} downloadDir=${LocalMusicDebugLog.quote(_downloadDirectory)} mediaStore=$androidMediaStoreEnabled files=${_files.length} scraped=${_scrapedIdentity.length}',
    );
    await SecurityScopedDirectory.restore();
    await _pruneMissingFiles();
    _initialized = true;
    LocalMusicDebugLog.info(
      'library.init.finish',
      'files=${_files.length} scraped=${_scrapedIdentity.length}',
    );
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

  /// 启用并扫描 Android MediaStore。默认 Android 本地音乐入口优先走这里。
  Future<int> enableAndroidMediaStore({
    void Function(int scanned, int total)? onProgress,
  }) async {
    await _storage.setBool(_androidMediaStoreEnabledKey, true);
    return rescanAndroidMediaStore(onProgress: onProgress);
  }

  Future<int> rescanAndroidMediaStore({
    void Function(int scanned, int total)? onProgress,
  }) async {
    LocalMusicDebugLog.info(
      'library.android_mediastore.start',
      'enabled=$androidMediaStoreEnabled',
    );
    final rawTracks = await AndroidDirectoryAccess.scanMediaStore();
    final tracks = rawTracks.map(_androidTrackFromMap).toList(growable: false);
    LocalMusicDebugLog.info(
      'library.android_mediastore.loaded',
      'tracks=${tracks.length}',
    );
    return _upsertPlatformTracks(
      source: 'mediaStore',
      tracks: tracks,
      onProgress: onProgress,
      staleFilter: (entry) => entry['androidSource'] == 'mediaStore',
    );
  }

  Future<int> addAndroidSafDirectory(
    String directoryPath, {
    void Function(int scanned, int total)? onProgress,
  }) async {
    LocalMusicDebugLog.info(
      'library.android_saf.start',
      'directory=${LocalMusicDebugLog.quote(directoryPath)}',
    );
    if (!_directories.contains(directoryPath)) {
      _directories = [..._directories, directoryPath];
      await _persistDirectories();
    }
    final rawTracks = await AndroidDirectoryAccess.scanSelectedDirectory();
    final tracks = rawTracks
        .map((entry) => _androidTrackFromMap(entry, safRoot: directoryPath))
        .toList(growable: false);
    LocalMusicDebugLog.info(
      'library.android_saf.loaded',
      'directory=${LocalMusicDebugLog.quote(directoryPath)} tracks=${tracks.length}',
    );
    return _upsertPlatformTracks(
      source: 'saf',
      tracks: tracks,
      onProgress: onProgress,
      staleFilter: (entry) =>
          entry['androidSource'] == 'saf' && entry['safRoot'] == directoryPath,
    );
  }

  LocalTrack _androidTrackFromMap(
    Map<String, dynamic> entry, {
    String? safRoot,
  }) {
    final fileName = entry['fileName']?.toString() ?? '';
    final path = entry['path']?.toString().trim() ?? '';
    final contentUri = entry['contentUri']?.toString();
    final modifiedMillis = _asInt(entry['modifiedAtMillis']);
    final durationMillis = _asInt(entry['durationMillis']);
    final bitrate = _asNullableInt(entry['bitrate']);
    final title =
        _cleanAndroidText(entry['title']) ?? titleFromFileName(fileName);
    final artist = _cleanAndroidArtist(entry['artist']);
    return LocalTrack(
      path: path.isNotEmpty ? path : contentUri ?? '',
      fileName: fileName.isNotEmpty ? fileName : titleFromFileName(path),
      extension: entry['extension']?.toString() ?? _extensionOf(fileName),
      size: _asInt(entry['size']),
      modifiedAt: modifiedMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(modifiedMillis)
          : DateTime.fromMillisecondsSinceEpoch(0),
      title: title,
      artist: artist ?? '未知歌手',
      album: _cleanAndroidText(entry['album']) ?? '',
      duration: Duration(milliseconds: durationMillis),
      bitrate: bitrate,
      hasEmbeddedTags:
          _cleanAndroidText(entry['title']) != null && artist != null,
      hasEmbeddedArtwork: false,
      contentUri: contentUri,
      androidSource: entry['androidSource']?.toString(),
      safRoot: safRoot ?? entry['safRoot']?.toString(),
      mimeType: entry['mimeType']?.toString(),
    );
  }

  Future<int> _upsertPlatformTracks({
    required String source,
    required List<LocalTrack> tracks,
    required bool Function(Map<String, dynamic> entry) staleFilter,
    void Function(int scanned, int total)? onProgress,
  }) async {
    final discoveredPaths = <String>{};
    var invalidatedChanged = 0;
    for (var index = 0; index < tracks.length; index++) {
      final track = tracks[index];
      if (track.path.isEmpty) continue;
      discoveredPaths.add(track.path);
      final previous = _files[track.path];
      final previousModified = DateTime.tryParse(
        previous?['modifiedAt']?.toString() ?? '',
      );
      if (previous != null &&
          (previous['size'] != track.size ||
              previousModified != track.modifiedAt)) {
        _scrapedIdentity.remove(track.path);
        invalidatedChanged++;
        LocalMusicDebugLog.warning(
          'library.platform_file_changed',
          'source=$source path=${LocalMusicDebugLog.quote(track.path)} oldSize=${previous['size']} newSize=${track.size}',
        );
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
        if (track.contentUri != null && track.contentUri!.isNotEmpty)
          'contentUri': track.contentUri,
        if (track.androidSource != null && track.androidSource!.isNotEmpty)
          'androidSource': track.androidSource,
        if (track.safRoot != null && track.safRoot!.isNotEmpty)
          'safRoot': track.safRoot,
        if (track.mimeType != null && track.mimeType!.isNotEmpty)
          'mimeType': track.mimeType,
      };
      LocalMusicDebugLog.info(
        'library.platform_index.upsert',
        'source=$source ${LocalMusicDebugLog.indexedFile(_files[track.path]!)}',
      );
      onProgress?.call(index + 1, tracks.length);
    }
    final stalePaths = _files.entries
        .where(
          (entry) =>
              staleFilter(entry.value) && !discoveredPaths.contains(entry.key),
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    if (stalePaths.isNotEmpty) {
      LocalMusicDebugLog.warning(
        'library.platform_stale_removed',
        "source=$source count=${stalePaths.length} sample=${stalePaths.take(5).map(LocalMusicDebugLog.quote).join(' | ')}",
      );
    }
    for (final path in stalePaths) {
      _files.remove(path);
      _scrapedIdentity.remove(path);
    }
    await Future.wait([_persistIndex(), _persistScrapedIdentity()]);
    LocalMusicDebugLog.info(
      'library.platform_scan.finish',
      'source=$source tracks=${tracks.length} invalidated=$invalidatedChanged stale=${stalePaths.length} files=${_files.length}',
    );
    return tracks.length;
  }

  String? _cleanAndroidText(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == '<unknown>') return null;
    return text;
  }

  String? _cleanAndroidArtist(Object? value) {
    final text = _cleanAndroidText(value);
    if (text == null) return null;
    final normalized = text.toLowerCase();
    if (normalized == 'unknown' ||
        normalized == 'unknown artist' ||
        text == '未知歌手' ||
        text == '未知艺术家') {
      return null;
    }
    return text;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asNullableInt(Object? value) {
    if (value == null) return null;
    final parsed = _asInt(value);
    return parsed <= 0 ? null : parsed;
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot >= 0 && dot < fileName.length - 1
        ? fileName.substring(dot + 1).toLowerCase()
        : '';
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
    for (final entry in _files.entries) {
      final path = entry.key;
      final value = entry.value;
      final contentUri = value['contentUri']?.toString();
      final androidSource = value['androidSource']?.toString();
      // MediaStore/SAF entries may be content backed and are validated by their
      // own rescans. Do not delete them just because dart:io cannot stat them.
      if ((androidSource == 'mediaStore' || androidSource == 'saf') &&
          contentUri != null &&
          contentUri.isNotEmpty) {
        continue;
      }
      if (Uri.tryParse(path)?.scheme == 'content') continue;
      if (!await File(path).exists()) missing.add(path);
    }
    if (missing.isEmpty) return;
    LocalMusicDebugLog.warning(
      'library.prune_missing',
      "count=${missing.length} sample=${missing.take(5).map(LocalMusicDebugLog.quote).join(' | ')}",
    );
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
    LocalMusicDebugLog.info(
      'library.add_directory.start',
      'directory=${LocalMusicDebugLog.quote(directoryPath)} knownDirs=${_directories.length}',
    );
    if (!_directories.contains(directoryPath)) {
      _directories = [..._directories, directoryPath];
      await _persistDirectories();
      LocalMusicDebugLog.info(
        'library.directory.persisted',
        'directory=${LocalMusicDebugLog.quote(directoryPath)} dirs=${_directories.length}',
      );
    }
    final discoveredPaths = <String>{};
    var skippedUnchanged = 0;
    var invalidatedChanged = 0;
    final tracks = await _scanner.scanDirectory(
      directoryPath,
      onDiscoveredPath: discoveredPaths.add,
      shouldSkip: (path) {
        final entry = _files[path];
        if (entry == null) return false;
        try {
          final stat = File(path).statSync();
          final indexedModified = DateTime.tryParse(
            entry['modifiedAt']?.toString() ?? '',
          );
          if (entry['size'] != stat.size || indexedModified != stat.modified) {
            _scrapedIdentity.remove(path);
            invalidatedChanged++;
            LocalMusicDebugLog.warning(
              'library.file_changed',
              'path=${LocalMusicDebugLog.quote(path)} oldSize=${entry['size']} newSize=${stat.size} oldModified=${LocalMusicDebugLog.quote(indexedModified)} newModified=${stat.modified.toIso8601String()}',
            );
            return false;
          }
        } catch (error) {
          LocalMusicDebugLog.warning(
            'library.file_stat_error',
            'path=${LocalMusicDebugLog.quote(path)} error=$error',
          );
          return false;
        }
        final identity = _scrapedIdentity[path];
        final hasLyrics = identity?['lyrics']?.toString().isNotEmpty == true;
        final hasArtwork = identity?['artwork']?.toString().isNotEmpty == true;
        // 歌词和封面分别刮削；不能因为已有歌词就跳过缺封面的文件。
        final shouldSkip = hasLyrics && hasArtwork;
        if (shouldSkip) {
          skippedUnchanged++;
        } else {
          LocalMusicDebugLog.info(
            'library.rescrape_needed',
            'path=${LocalMusicDebugLog.quote(path)} hasLyrics=$hasLyrics hasArtwork=$hasArtwork',
          );
        }
        return shouldSkip;
      },
      onProgress: onProgress,
    );
    for (final track in tracks) {
      String? artworkPath = _files[track.path]?['artwork']?.toString();
      final embedded = track.embeddedArtwork;
      if (embedded != null && embedded.isNotEmpty) {
        artworkPath = await _persistEmbeddedArtwork(track.path, embedded);
        LocalMusicDebugLog.info(
          'library.embedded_artwork.persisted',
          'bytes=${embedded.length} path=${LocalMusicDebugLog.quote(artworkPath)} track=${LocalMusicDebugLog.quote(track.path)}',
        );
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
      LocalMusicDebugLog.info(
        'library.index.upsert',
        LocalMusicDebugLog.indexedFile(_files[track.path]!),
      );
    }
    final prefix = directoryPath.endsWith(Platform.pathSeparator)
        ? directoryPath
        : '$directoryPath${Platform.pathSeparator}';
    final stalePaths = _files.keys
        .where(
          (path) => path.startsWith(prefix) && !discoveredPaths.contains(path),
        )
        .toList(growable: false);
    if (stalePaths.isNotEmpty) {
      LocalMusicDebugLog.warning(
        'library.stale_removed',
        "count=${stalePaths.length} sample=${stalePaths.take(5).map(LocalMusicDebugLog.quote).join(' | ')}",
      );
    }
    for (final path in stalePaths) {
      _files.remove(path);
      _scrapedIdentity.remove(path);
    }
    await _persistIndex();
    LocalMusicDebugLog.info(
      'library.add_directory.finish',
      'directory=${LocalMusicDebugLog.quote(directoryPath)} parsed=${tracks.length} discovered=${discoveredPaths.length} skipped=$skippedUnchanged invalidated=$invalidatedChanged stale=${stalePaths.length} files=${_files.length}',
    );
    return tracks.length;
  }

  Future<String> _persistEmbeddedArtwork(
    String trackPath,
    Uint8List bytes,
  ) async {
    final dir = await (_artworkDir ??= _createArtworkDir());
    final hash = sha1.convert(utf8.encode(trackPath)).toString();
    final file = File('${dir.path}/$hash.jpg');
    if (await file.exists()) {
      LocalMusicDebugLog.info(
        'library.embedded_artwork.cache_hit',
        'track=${LocalMusicDebugLog.quote(trackPath)} path=${LocalMusicDebugLog.quote(file.path)}',
      );
      return file.path;
    }
    await file.writeAsBytes(bytes, flush: true);
    LocalMusicDebugLog.info(
      'library.embedded_artwork.cache_write',
      'track=${LocalMusicDebugLog.quote(trackPath)} path=${LocalMusicDebugLog.quote(file.path)} bytes=${bytes.length}',
    );
    return file.path;
  }

  Future<Directory> _createArtworkDir() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/local_artwork');
    await dir.create(recursive: true);
    return dir;
  }

  bool _isAndroidSafDirectory(String directoryPath) {
    if (directoryPath.startsWith('content://')) return true;
    return _files.values.any(
      (entry) =>
          entry['androidSource'] == 'saf' &&
          entry['safRoot']?.toString() == directoryPath,
    );
  }

  /// 重新扫描全部目录（用于显式刷新），含下载目录。
  Future<int> rescanAll({
    void Function(int scanned, int total)? onProgress,
  }) async {
    LocalMusicDebugLog.info(
      'library.rescan_all.start',
      'directories=${_directories.length} downloadDir=${LocalMusicDebugLog.quote(_downloadDirectory)} mediaStore=$androidMediaStoreEnabled',
    );
    var added = 0;
    if (androidMediaStoreEnabled) {
      added += await rescanAndroidMediaStore(onProgress: onProgress);
    }
    final downloadDir = _downloadDirectory;
    if (downloadDir != null && !_directories.contains(downloadDir)) {
      added += await addDirectory(downloadDir, onProgress: onProgress);
    }
    for (final directoryPath in List.of(_directories)) {
      if (_isAndroidSafDirectory(directoryPath)) {
        added += await addAndroidSafDirectory(
          directoryPath,
          onProgress: onProgress,
        );
      } else {
        added += await addDirectory(directoryPath, onProgress: onProgress);
      }
    }
    LocalMusicDebugLog.info(
      'library.rescan_all.finish',
      'added=$added files=${_files.length} scraped=${_scrapedIdentity.length}',
    );
    return added;
  }

  /// 仅重新扫描下载目录（下载完成后调用，增量更新）。
  Future<int> rescanDownloadDirectory() async {
    final downloadDir = _downloadDirectory;
    if (downloadDir == null) {
      LocalMusicDebugLog.info(
        'library.rescan_download.skip',
        'downloadDir=null',
      );
      return 0;
    }
    LocalMusicDebugLog.info(
      'library.rescan_download.start',
      'directory=${LocalMusicDebugLog.quote(downloadDir)}',
    );
    final added = await addDirectory(downloadDir);
    LocalMusicDebugLog.info(
      'library.rescan_download.finish',
      'added=$added files=${_files.length}',
    );
    return added;
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
    if (!await file.exists()) {
      LocalMusicDebugLog.warning(
        'library.download_upsert.missing_file',
        'path=${LocalMusicDebugLog.quote(path)}',
      );
      return;
    }
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
    LocalMusicDebugLog.info(
      'library.download_upsert.persist',
      'path=${LocalMusicDebugLog.quote(path)} file=${LocalMusicDebugLog.quote(fileName)} title=${LocalMusicDebugLog.quote(title)} artist=${LocalMusicDebugLog.quote(artist)} platform=$platform songmid=${LocalMusicDebugLog.quote(songmid)} hash=${LocalMusicDebugLog.quote(hash)} artwork=${LocalMusicDebugLog.present(artwork)}',
    );
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
    await Future.wait([
      _persistDirectories(),
      _persistIndex(),
      _persistScrapedIdentity(),
    ]);
  }

  /// 记录刮削到的在线身份（songmid/hash/artwork/lyricsUrl 等）。
  ///
  /// The side-table identity is enough for [songs], but Android 16 can keep the
  /// raw file index at filename/未知歌手 when platform metadata reads are stale or
  /// file tag writes are deferred. Mirror verified scrape labels into the index
  /// as well so every local list has the same visible metadata immediately.
  Future<void> applyScrapedIdentity(
    String path,
    Map<String, dynamic> identity,
  ) async {
    LocalMusicDebugLog.info(
      'library.scrape_identity.apply.start',
      'path=${LocalMusicDebugLog.quote(path)} ${LocalMusicDebugLog.identity(identity)}',
    );
    _scrapedIdentity[path] = Map<String, dynamic>.from(identity);
    final current = _files[path];
    if (current != null) {
      final title = _nonEmptyString(identity['name']);
      final artist = _nonEmptyString(identity['singer']);
      final album = _nonEmptyString(identity['album']);
      final artwork = _nonEmptyString(identity['artwork']);
      _files[path] = {
        ...current,
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
        if (artwork != null) 'artwork': artwork,
      };
      LocalMusicDebugLog.info(
        'library.scrape_identity.mirror_index',
        'path=${LocalMusicDebugLog.quote(path)} title=${LocalMusicDebugLog.quote(title)} artist=${LocalMusicDebugLog.quote(artist)} album=${LocalMusicDebugLog.quote(album)} artwork=${LocalMusicDebugLog.present(artwork)}',
      );
      await Future.wait([_persistIndex(), _persistScrapedIdentity()]);
      LocalMusicDebugLog.info(
        'library.scrape_identity.apply.finish',
        'path=${LocalMusicDebugLog.quote(path)} mirrored=true scraped=${_scrapedIdentity.length}',
      );
      return;
    }
    LocalMusicDebugLog.warning(
      'library.scrape_identity.no_index_entry',
      'path=${LocalMusicDebugLog.quote(path)}',
    );
    await _persistScrapedIdentity();
    LocalMusicDebugLog.info(
      'library.scrape_identity.apply.finish',
      'path=${LocalMusicDebugLog.quote(path)} mirrored=false scraped=${_scrapedIdentity.length}',
    );
  }

  String? _nonEmptyString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// 下载完成后补充在线封面：为没有内嵌封面/刮削封面的条目写入在线 artwork，
  /// 使下载歌曲立即可见封面（不必等刮削）。
  Future<void> applyDownloadArtwork(Map<String, String> pathToArtwork) async {
    var changed = false;
    var applied = 0;
    var skippedExisting = 0;
    var missingIndex = 0;
    for (final entry in pathToArtwork.entries) {
      final current = _files[entry.key];
      if (current == null) {
        missingIndex++;
        continue;
      }
      if (current['artwork']?.toString().isNotEmpty == true) {
        skippedExisting++;
        continue;
      }
      final identity = _scrapedIdentity[entry.key];
      if (identity?['artwork']?.toString().isNotEmpty == true) {
        skippedExisting++;
        continue;
      }
      _files[entry.key] = {...current, 'artwork': entry.value};
      LocalMusicDebugLog.info(
        'library.download_artwork.apply',
        'path=${LocalMusicDebugLog.quote(entry.key)} artwork=${LocalMusicDebugLog.quote(entry.value)}',
      );
      applied++;
      changed = true;
    }
    if (changed) await _persistIndex();
    LocalMusicDebugLog.info(
      'library.download_artwork.finish',
      'input=${pathToArtwork.length} applied=$applied skippedExisting=$skippedExisting missingIndex=$missingIndex changed=$changed',
    );
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
    final contentUri = entry['contentUri']?.toString();
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
      id: 'local:${sha1.convert(utf8.encode(path)).toString()}',
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
      // MediaStore/SAF entries prefer their content URI for Android scoped
      // storage; plain file-backed tracks keep file:// URLs.
      url: contentUri != null && contentUri.isNotEmpty
          ? contentUri
          : Uri.file(path).toString(),
      lyricsUrl: lyricsUrl,
      isPlayable: true,
      songmid: songmid,
      hash: hash,
      meta: {
        'filePath': path,
        if (contentUri != null && contentUri.isNotEmpty)
          'contentUri': contentUri,
        if (entry['androidSource']?.toString().isNotEmpty == true)
          'androidSource': entry['androidSource']?.toString(),
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
