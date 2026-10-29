import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;

import '../../../core/audio/replay_gain.dart';
import 'local_music_debug_log.dart';
import 'local_scan_rules.dart';

/// 支持的音频扩展名（小写，不含点）。
const Set<String> kLocalAudioExtensions = {
  'mp3',
  'flac',
  'm4a',
  'aac',
  'wav',
  'ogg',
  'opus',
  'wma',
  'ape',
  'aiff',
  'alac',
};

/// 从文件名剥离扩展名后的标题。
/// 下载目录文件名为「歌曲名-短标识-版本号.ext」，回退标题时去掉尾部标识。
String titleFromFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  final trimmed = RegExp(r'(.+)-[0-9A-Za-z]{8}-\d+$').firstMatch(base);
  if (trimmed != null && trimmed.group(1)!.isNotEmpty) {
    return trimmed.group(1)!;
  }
  return base;
}

/// 扫描结果：单个本地音频文件 + 解析出的元数据。
class LocalTrack {
  const LocalTrack({
    required this.path,
    required this.fileName,
    required this.extension,
    required this.size,
    required this.modifiedAt,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.bitrate,
    this.hasEmbeddedTags = true,
    this.hasEmbeddedArtwork = false,
    this.embeddedArtwork,
    this.folderArtworkPath,
    this.contentUri,
    this.androidSource,
    this.safRoot,
    this.mimeType,
    this.replayGainDb,
  });

  final String path;
  final String fileName;
  final String extension;
  final int size;
  final DateTime modifiedAt;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final int? bitrate;
  final bool hasEmbeddedTags;
  final bool hasEmbeddedArtwork;
  final Uint8List? embeddedArtwork;

  /// 同目录的 `cover.jpg` / `folder.jpg` 等文件夹封面（绝对路径）。
  ///
  /// 只在文件没有内嵌封面时才有值。老式 CD 抓轨和很多整理过的音乐库都
  /// 采用「一张专辑目录放一张图」的做法，没有这个回退就只能显示占位图。
  final String? folderArtworkPath;

  final String? contentUri;
  final String? androidSource;
  final String? safRoot;
  final String? mimeType;

  /// ReplayGain 曲目增益（dB）。null 表示文件里没有这个标签。
  final double? replayGainDb;

  LocalTrack copyWith({String? title, String? artist, String? album}) {
    return LocalTrack(
      path: path,
      fileName: fileName,
      extension: extension,
      size: size,
      modifiedAt: modifiedAt,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration,
      bitrate: bitrate,
      hasEmbeddedTags: hasEmbeddedTags,
      hasEmbeddedArtwork: hasEmbeddedArtwork,
      embeddedArtwork: embeddedArtwork,
      folderArtworkPath: folderArtworkPath,
      contentUri: contentUri,
      androidSource: androidSource,
      safRoot: safRoot,
      mimeType: mimeType,
      replayGainDb: replayGainDb,
    );
  }
}

/// Serializable result of parsing one file's tags on a worker isolate.
///
/// The audio_metadata_reader objects are not sendable, so the worker narrows
/// them to plain values before crossing the isolate boundary.
class LocalTagProbe {
  const LocalTagProbe({
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.bitrate,
    this.artwork,
    this.replayGainDb,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final int? bitrate;
  final Uint8List? artwork;
  final double? replayGainDb;
}

/// Argument for [probeTagsOnWorker].
class LocalScanProbeRequest {
  const LocalScanProbeRequest({required this.path, required this.getImage});

  final String path;
  final bool getImage;
}

/// 读文件开头一段解析 ReplayGain。
///
/// 只读前 512 KB：标签块远小于这个量级，而整文件读进来会在大文件上
/// 把一次扫描变成磁盘压力测试。必须是顶层函数——它要在 worker isolate 里跑。
double? probeReplayGainDb(File file) {
  RandomAccessFile? handle;
  try {
    handle = file.openSync();
    final head = handle.readSync(512 * 1024);
    return readReplayGainDb(head);
  } catch (_) {
    return null;
  } finally {
    try {
      handle?.closeSync();
    } catch (_) {
      // 已经关闭或句柄失效，忽略。
    }
  }
}

AudioMetadata _readMetadataWithArtworkFallbackInWorker(File file) {
  try {
    return readMetadata(file, getImage: true);
  } on Object {
    // A broken embedded picture must not hide otherwise valid text tags.
    return readMetadata(file);
  }
}

/// Runs on a worker isolate.
///
/// `readMetadata` is a *synchronous* call that parses the whole tag block —
/// including embedded artwork — before it returns. Calling it on the UI isolate
/// froze the app for the duration of a scan (seconds on a large library), so it
/// must stay off the main isolate. This has to remain a top-level function:
/// `compute` requires an entry point it can re-resolve on the new isolate.
LocalTagProbe probeTagsOnWorker(LocalScanProbeRequest request) {
  final file = File(request.path);
  try {
    final tag = _readMetadataWithArtworkFallbackInWorker(file);
    final pictures = tag.pictures;
    final artwork = pictures.isNotEmpty ? pictures.first.bytes : null;
    final bitrate = tag.bitrate;
    return LocalTagProbe(
      title: tag.title,
      artist: tag.artist,
      album: tag.album,
      durationMs: tag.duration?.inMilliseconds,
      bitrate: bitrate is int && bitrate > 0 ? bitrate : null,
      artwork: artwork,
      replayGainDb: probeReplayGainDb(file),
    );
  } on Object {
    // A malformed or unsupported tag block must not drop the file: the caller
    // falls back to filename-derived metadata.
    return const LocalTagProbe();
  }
}

/// 递归扫描目录中的音频文件并用 audiotags 解析元数据。
/// 通过 [shouldSkip] 跳过已知未变更的文件，实现增量扫描。
class LocalMusicScanner {
  LocalMusicScanner({this.rules = const LocalScanRules()});

  /// 扫描过滤规则。可在两次扫描之间替换，下一次扫描立即生效。
  LocalScanRules rules;

  /// [scanDirectory] 进度回调的最小间隔，避免每个文件都触发一次 UI 重建。
  static const int _progressIntervalMs = 100;

  /// 文件夹封面的文件名（不含扩展名），按常见程度排序。
  static const List<String> _folderArtworkNames = [
    'cover',
    'folder',
    'front',
    'album',
    'artwork',
  ];

  /// 只认图片格式：同目录的 `cover.txt` 之类不该被当成封面。
  static const List<String> _folderArtworkExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  /// 目录 → 封面路径（null 表示该目录没有）。
  ///
  /// 一张专辑目录里的每首歌都查同一批文件名，缓存能省掉成百上千次 `exists`。
  final Map<String, String?> _folderArtworkCache = {};

  /// 找同目录的文件夹封面，找不到返回 null。
  Future<String?> _folderArtworkFor(String audioPath) async {
    final slash = audioPath.lastIndexOf('/');
    final backslash = audioPath.lastIndexOf(r'\');
    final separator = slash > backslash ? slash : backslash;
    if (separator < 0) return null;
    final prefix = audioPath.substring(0, separator + 1);
    if (_folderArtworkCache.containsKey(prefix)) {
      return _folderArtworkCache[prefix];
    }
    String? found;
    outer:
    for (final name in _folderArtworkNames) {
      for (final extension in _folderArtworkExtensions) {
        // Android 与 Windows 的文件系统大小写不敏感，Linux 敏感。两种都试，
        // 成本只是一次 stat。
        for (final candidate in [
          '$name.$extension',
          '$name.${extension.toUpperCase()}',
        ]) {
          try {
            final file = File('$prefix$candidate');
            if (await file.exists()) {
              found = file.path;
              break outer;
            }
          } catch (_) {
            // 权限不足或路径非法：继续试下一个候选。
          }
        }
      }
    }
    _folderArtworkCache[prefix] = found;
    return found;
  }

  /// 暴露给测试：在 worker isolate 上解析单个文件的标签。
  @visibleForTesting
  static Future<LocalTagProbe> debugProbeTags(String path) => compute(
    probeTagsOnWorker,
    LocalScanProbeRequest(path: path, getImage: true),
  );

  bool _isAudioFile(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return kLocalAudioExtensions.contains(
      name.substring(dot + 1).toLowerCase(),
    );
  }

  Future<List<FileSystemEntity>> _walk(Directory directory) async {
    final results = <FileSystemEntity>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory) {
          // 排除目录整枝跳过：用户把「语音备忘」「播客缓存」放进音乐目录时，
          // 一条条过滤比直接不进去慢得多。
          if (rules.excludes(entity.path)) {
            LocalMusicDebugLog.info(
              'scan.excluded_dir',
              'directory=${LocalMusicDebugLog.quote(entity.path)}',
            );
            continue;
          }
          results.addAll(await _walk(entity));
        } else if (entity is File &&
            _isAudioFile(entity.uri.pathSegments.last)) {
          results.add(entity);
        }
      }
    } catch (error, stackTrace) {
      LocalMusicDebugLog.warning(
        'scan.walk_failed',
        'directory=${LocalMusicDebugLog.quote(directory.path)} error=$error',
        stackTrace: stackTrace,
      );
      // 目录不可读或已被删除：跳过该分支，保留已收集的文件。
    }
    return results;
  }

  /// 扫描目录下所有音频文件并解析元数据。
  /// [shouldSkip] 返回 true 时跳过该文件的重新解析（用于增量扫描）。
  /// 判定是否需要跳过通常要读一次文件状态，因此该回调是异步的：逐文件
  /// 同步 stat 同样会阻塞 UI 线程。
  Future<List<LocalTrack>> scanDirectory(
    String directoryPath, {
    Future<bool> Function(String path)? shouldSkip,
    void Function(String path)? onDiscoveredPath,
    void Function(int scanned, int total)? onProgress,
  }) async {
    final directory = Directory(directoryPath);
    LocalMusicDebugLog.info(
      'scan.start',
      'directory=${LocalMusicDebugLog.quote(directoryPath)}',
    );
    if (!await directory.exists()) {
      LocalMusicDebugLog.warning(
        'scan.missing_directory',
        'directory=${LocalMusicDebugLog.quote(directoryPath)}',
      );
      throw StateError('目录不存在: $directoryPath');
    }
    final files = await _walk(directory);
    LocalMusicDebugLog.info(
      'scan.discovered',
      'directory=${LocalMusicDebugLog.quote(directoryPath)} files=${files.length}',
    );
    final tracks = <LocalTrack>[];
    // 去重键 → tracks 下标；命中时用体积更大的那份替换。
    final duplicateIndexes = <String, int>{};
    // Throttle progress: the UI rebuilds its whole list on each tick, and
    // reporting every single file turned a large scan into thousands of
    // rebuilds. The final tick is always emitted so the count lands exactly.
    final progressClock = Stopwatch()..start();
    var lastProgressMs = -_progressIntervalMs;
    void emitProgress(int scanned) {
      final elapsedMs = progressClock.elapsedMilliseconds;
      if (elapsedMs - lastProgressMs < _progressIntervalMs &&
          scanned < files.length) {
        return;
      }
      lastProgressMs = elapsedMs;
      onProgress?.call(scanned, files.length);
    }

    for (var index = 0; index < files.length; index++) {
      final file = files[index] as File;
      final path = file.path;
      onDiscoveredPath?.call(path);
      if (await (shouldSkip?.call(path) ?? Future<bool>.value(false))) {
        LocalMusicDebugLog.info(
          'scan.skip_unchanged',
          'index=${index + 1}/${files.length} path=${LocalMusicDebugLog.quote(path)}',
        );
        emitProgress(index + 1);
        continue;
      }
      final track = await _readTrack(file);
      if (track == null) {
        LocalMusicDebugLog.warning(
          'scan.drop_file',
          'index=${index + 1}/${files.length} path=${LocalMusicDebugLog.quote(path)}',
        );
        emitProgress(index + 1);
        continue;
      }
      if (!rules.allows(sizeBytes: track.size, duration: track.duration)) {
        LocalMusicDebugLog.info(
          'scan.filtered',
          'index=${index + 1}/${files.length} ${LocalMusicDebugLog.track(track)}',
        );
        emitProgress(index + 1);
        continue;
      }
      if (rules.skipDuplicates) {
        final key = duplicateKeyOf(track);
        final existing = key == null ? null : duplicateIndexes[key];
        if (key != null && existing != null) {
          // 同一首歌通常有一份低码率、一份高码率。保留体积大的那份，
          // 而不是保留先扫到的那份——扫描顺序取决于文件系统，不可依赖。
          if (track.size > tracks[existing].size) {
            tracks[existing] = track;
          }
          LocalMusicDebugLog.info(
            'scan.duplicate',
            'index=${index + 1}/${files.length} key=${LocalMusicDebugLog.quote(key)}',
          );
          emitProgress(index + 1);
          continue;
        }
        if (key != null) duplicateIndexes[key] = tracks.length;
      }
      tracks.add(track);
      LocalMusicDebugLog.info(
        'scan.parsed',
        'index=${index + 1}/${files.length} ${LocalMusicDebugLog.track(track)}',
      );
      emitProgress(index + 1);
    }
    LocalMusicDebugLog.info(
      'scan.finish',
      'directory=${LocalMusicDebugLog.quote(directoryPath)} parsed=${tracks.length} files=${files.length}',
    );
    return tracks;
  }

  Future<LocalTrack?> _readTrack(File file) async {
    final fileName = file.uri.pathSegments.last;
    final dot = fileName.lastIndexOf('.');
    final extension = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : '';
    try {
      // 异步 stat：原先的同步 stat 每个文件都会阻塞 UI 线程一次。
      final stat = await file.stat();
      // 标签与内嵌封面解析放到 worker isolate，避免扫描期间卡住 UI。
      // 纯 Dart 解析器不引入平台原生库，避免 Android/iOS 链接阶段失败。
      final tag = await compute(
        probeTagsOnWorker,
        LocalScanProbeRequest(path: file.path, getImage: true),
      );
      final title = _nonEmpty(tag.title) ?? titleFromFileName(fileName);
      final artist = _nonEmpty(tag.artist) ?? '未知歌手';
      final album = _nonEmpty(tag.album) ?? '';
      final artwork = tag.artwork;
      final hasEmbeddedArtwork = artwork != null && artwork.isNotEmpty;
      return LocalTrack(
        path: file.path,
        fileName: fileName,
        extension: extension,
        size: stat.size,
        modifiedAt: stat.modified,
        title: title,
        artist: artist,
        album: album,
        duration: Duration(milliseconds: tag.durationMs ?? 0),
        bitrate: tag.bitrate,
        hasEmbeddedTags:
            _nonEmpty(tag.title) != null && _nonEmpty(tag.artist) != null,
        hasEmbeddedArtwork: hasEmbeddedArtwork,
        embeddedArtwork: artwork,
        // 没有内嵌封面时退回同目录的专辑图（CD 抓轨的常见布局）。
        folderArtworkPath: hasEmbeddedArtwork
            ? null
            : await _folderArtworkFor(file.path),
        replayGainDb: tag.replayGainDb,
      );
    } catch (error, stackTrace) {
      LocalMusicDebugLog.warning(
        'scan.metadata_failed',
        'file=${LocalMusicDebugLog.quote(fileName)} error=$error',
        stackTrace: stackTrace,
      );
      // 某些 Windows 编码器和 iOS 文件类型无法读取 tag，但文件本身仍
      // 可以播放。保留文件并用文件名作为低置信度刮削输入，不要整首丢掉。
      try {
        final stat = await file.stat();
        final track = LocalTrack(
          path: file.path,
          fileName: fileName,
          extension: extension,
          size: stat.size,
          modifiedAt: stat.modified,
          title: titleFromFileName(fileName),
          artist: '未知歌手',
          album: '',
          duration: Duration.zero,
          bitrate: null,
          hasEmbeddedTags: false,
          // 标签都读不出来的文件更可能是老格式，同目录封面往往是唯一的图。
          folderArtworkPath: await _folderArtworkFor(file.path),
        );
        LocalMusicDebugLog.warning(
          'scan.filename_fallback',
          LocalMusicDebugLog.track(track),
        );
        return track;
      } catch (fallbackError, fallbackStackTrace) {
        LocalMusicDebugLog.error(
          'scan.file_stat_failed',
          'file=${LocalMusicDebugLog.quote(fileName)} error=$fallbackError',
          stackTrace: fallbackStackTrace,
        );
        // 文件在扫描过程中被删除或无权访问。
        return null;
      }
    }
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
