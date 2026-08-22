import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

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
    );
  }
}

/// 递归扫描目录中的音频文件并用 audiotags 解析元数据。
/// 通过 [shouldSkip] 跳过已知未变更的文件，实现增量扫描。
class LocalMusicScanner {
  LocalMusicScanner();

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
          results.addAll(await _walk(entity));
        } else if (entity is File &&
            _isAudioFile(entity.uri.pathSegments.last)) {
          results.add(entity);
        }
      }
    } catch (error) {
      // 目录不可读或已被删除：跳过该分支，保留已收集的文件。
    }
    return results;
  }

  /// 扫描目录下所有音频文件并解析元数据。
  /// [shouldSkip] 返回 true 时跳过该文件的重新解析（用于增量扫描）。
  Future<List<LocalTrack>> scanDirectory(
    String directoryPath, {
    bool Function(String path)? shouldSkip,
    void Function(int scanned, int total)? onProgress,
  }) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw StateError('目录不存在: $directoryPath');
    }
    final files = await _walk(directory);
    final tracks = <LocalTrack>[];
    for (var index = 0; index < files.length; index++) {
      final file = files[index] as File;
      final path = file.path;
      if (shouldSkip?.call(path) ?? false) continue;
      final track = await _readTrack(file);
      if (track != null) tracks.add(track);
      onProgress?.call(index + 1, files.length);
    }
    return tracks;
  }

  Future<LocalTrack?> _readTrack(File file) async {
    final fileName = file.uri.pathSegments.last;
    final dot = fileName.lastIndexOf('.');
    final extension = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : '';
    try {
      final stat = await file.stat();
      // 纯 Dart 解析器不引入平台原生库，避免 Android/iOS 链接阶段失败。
      // 提取内嵌封面供本地音乐显示（无在线刮削时使用）。
      final tag = _readMetadataWithArtworkFallback(file);
      final title = tag.title ?? titleFromFileName(fileName);
      final artist = tag.artist ?? '未知歌手';
      final album = tag.album ?? '';
      final duration = tag.duration ?? Duration.zero;
      final pictures = tag.pictures;
      final artwork = pictures.isNotEmpty ? pictures.first.bytes : null;
      return LocalTrack(
        path: file.path,
        fileName: fileName,
        extension: extension,
        size: stat.size,
        modifiedAt: stat.modified,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        bitrate: _bitrateOf(tag),
        hasEmbeddedTags:
            tag.title?.trim().isNotEmpty == true &&
            tag.artist?.trim().isNotEmpty == true,
        hasEmbeddedArtwork: artwork != null && artwork.isNotEmpty,
        embeddedArtwork: artwork,
      );
    } catch (error) {
      // 某些 Windows 编码器和 iOS 文件类型无法读取 tag，但文件本身仍
      // 可以播放。保留文件并用文件名作为低置信度刮削输入，不要整首丢掉。
      try {
        final stat = await file.stat();
        return LocalTrack(
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
        );
      } catch (_) {
        // 文件在扫描过程中被删除或无权访问。
        return null;
      }
    }
  }

  dynamic _readMetadataWithArtworkFallback(File file) {
    try {
      return readMetadata(file, getImage: true);
    } catch (_) {
      // A broken embedded picture must not hide otherwise valid text tags.
      return readMetadata(file);
    }
  }

  int? _bitrateOf(dynamic tag) {
    final bitrate = tag.bitrate;
    return bitrate is int && bitrate > 0 ? bitrate : null;
  }
}
