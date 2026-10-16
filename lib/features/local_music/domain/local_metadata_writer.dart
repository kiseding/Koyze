import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Writes the identity found by the scraper back into writable audio formats.
/// Unsupported containers are left untouched; the library index still keeps
/// the scraped identity separately.
Future<bool> writeScrapedMetadata(
  String path, {
  required String title,
  required String artist,
  required String album,
  Uint8List? artwork,
  String artworkMimeType = 'image/jpeg',
}) async {
  final file = File(path);
  if (!await file.exists()) return false;
  try {
    final extension = path.split('.').last.toLowerCase();
    final noTagMp3 = extension == 'mp3' && _hasNoReadableTag(file);
    if (noTagMp3 && !_looksLikeMp3(file)) return false;
    final metadata = noTagMp3 ? Mp3Metadata() : readAllMetadata(file);
    metadata
      ..setTitle(title)
      ..setArtist(artist)
      ..setAlbum(album);
    if (artwork != null && artwork.isNotEmpty) {
      metadata.setPictures([
        Picture(artwork, artworkMimeType, PictureType.coverFront),
      ]);
    }
    dynamic verified;
    if (Platform.isAndroid && path.startsWith('/')) {
      // Android external-media paths may be backed by a SAF tree URI. Write
      // the fully updated file through ContentResolver when available.
      final temporary = File(
        '${(await getTemporaryDirectory()).path}/koyze-tag-${file.uri.pathSegments.last}.tmp',
      );
      try {
        await temporary.parent.create(recursive: true);
        await file.copy(temporary.path);
        if (noTagMp3 && metadata is Mp3Metadata) {
          Id3v4Writer().write(temporary, metadata);
        } else {
          writeMetadata(temporary, metadata);
        }
        final bytes = await temporary.readAsBytes();
        final channel = const MethodChannel('koyze/android_file_access');
        final written = await channel.invokeMethod<bool>('writeFileBytes', {
          'path': path,
          'bytes': bytes,
        });
        if (written != true) {
          // App-owned paths do not need SAF. Fall back to direct writing.
          if (noTagMp3 && metadata is Mp3Metadata) {
            Id3v4Writer().write(file, metadata);
          } else {
            writeMetadata(file, metadata);
          }
          verified = readMetadata(file, getImage: artwork != null);
        } else {
          // File(path) may be a stale view of a SAF-backed document. Verify
          // the bytes returned by ContentResolver instead of the stale path.
          final actual = await channel.invokeMethod<Uint8List>(
            'readFileBytes',
            {'path': path},
          );
          if (actual == null || actual.isEmpty) return false;
          await temporary.writeAsBytes(actual, flush: true);
        }
        verified = readMetadata(temporary, getImage: artwork != null);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } else if (noTagMp3 && metadata is Mp3Metadata) {
      Id3v4Writer().write(file, metadata);
      verified = readMetadata(file, getImage: artwork != null);
    } else {
      writeMetadata(file, metadata);
      verified = readMetadata(file, getImage: artwork != null);
    }
    // Verify the writer actually produced readable metadata. Some containers
    // are readable but do not support creating a new tag block.
    if (verified?.title?.trim() != title.trim() ||
        verified?.artist?.trim() != artist.trim()) {
      return false;
    }
    return true;
  } catch (error) {
    // Keep the index-based scrape result even when a container is read-only.
    // The caller can report this separately to the user.
    stderr.writeln('[LocalMetadataWriter] failed path=$path error=$error');
    return false;
  }
}

bool _hasNoReadableTag(File file) {
  final reader = file.openSync();
  try {
    return !MP3Parser.hasID3v2Tag(reader) && !MP3Parser.hasID3v1Tag(reader);
  } finally {
    reader.closeSync();
  }
}

bool _looksLikeMp3(File file) {
  final reader = file.openSync();
  try {
    if (reader.lengthSync() < 2) return false;
    final bytes = reader.readSync(2);
    return bytes.length == 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
  } finally {
    reader.closeSync();
  }
}
