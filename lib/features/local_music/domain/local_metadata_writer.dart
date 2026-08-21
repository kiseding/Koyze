import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

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
    if (noTagMp3 && metadata is Mp3Metadata) {
      Id3v4Writer().write(file, metadata);
    } else {
      writeMetadata(file, metadata);
    }
    return true;
  } catch (_) {
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
