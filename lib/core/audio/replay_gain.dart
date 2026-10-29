import 'dart:math' as math;
import 'dart:typed_data';

/// 从一个音频文件开头若干字节里读出 ReplayGain 的曲目增益（dB）。
///
/// `audio_metadata_reader` 不暴露 Vorbis Comment / TXXX 里的自定义字段，
/// 而 ReplayGain 恰好只存在这些字段里，所以这里自己解一层。
///
/// 支持两种最常见的存放方式：
/// * FLAC 的 Vorbis Comment：`REPLAYGAIN_TRACK_GAIN=-7.23 dB`
/// * MP3 的 ID3v2 `TXXX` 帧：描述 `REPLAYGAIN_TRACK_GAIN`，值为 `-7.23 dB`
///
/// 找不到就返回 null。**不抛异常**：标签坏掉不应该影响播放或扫描。
double? readReplayGainDb(Uint8List bytes) {
  if (bytes.length < 12) return null;
  try {
    if (_matchesAscii(bytes, 0, 'fLaC')) return _readFlac(bytes);
    if (_matchesAscii(bytes, 0, 'ID3')) return _readId3v2(bytes);
  } catch (_) {
    return null;
  }
  return null;
}

/// dB → 线性增益倍数。-7.23 dB ≈ 0.435。
double replayGainFactor(double gainDb) {
  if (!gainDb.isFinite) return 1;
  return math.pow(10, gainDb / 20).toDouble();
}

bool _matchesAscii(Uint8List bytes, int offset, String text) {
  if (offset + text.length > bytes.length) return false;
  for (var i = 0; i < text.length; i++) {
    if (bytes[offset + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

double? _parseGainValue(String value) {
  final match = RegExp(r'(-?\d+(?:\.\d+)?)').firstMatch(value);
  if (match == null) return null;
  final parsed = double.tryParse(match.group(1)!);
  if (parsed == null || !parsed.isFinite) return null;
  // 顺手挡住明显坏掉的数据（例如把字节长度写进了标签）。
  if (parsed.abs() > 40) return null;
  return parsed;
}

double? _readFlac(Uint8List bytes) {
  var offset = 4;
  while (offset + 4 <= bytes.length) {
    final header = bytes[offset];
    final isLast = (header & 0x80) != 0;
    final type = header & 0x7F;
    final length =
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    offset += 4;
    if (offset + length > bytes.length) return null;
    if (type == 4) {
      final gain = _readVorbisComment(bytes, offset, length);
      if (gain != null) return gain;
    }
    offset += length;
    if (isLast) break;
  }
  return null;
}

double? _readVorbisComment(Uint8List bytes, int start, int length) {
  final end = start + length;
  var offset = start;
  if (offset + 4 > end) return null;
  final vendorLength = _leUint32(bytes, offset);
  offset += 4 + vendorLength;
  if (offset + 4 > end) return null;
  final count = _leUint32(bytes, offset);
  offset += 4;
  for (var i = 0; i < count; i++) {
    if (offset + 4 > end) return null;
    final entryLength = _leUint32(bytes, offset);
    offset += 4;
    if (offset + entryLength > end) return null;
    final entry = String.fromCharCodes(
      bytes.sublist(offset, offset + entryLength),
    );
    offset += entryLength;
    final separator = entry.indexOf('=');
    if (separator <= 0) continue;
    final key = entry.substring(0, separator).toUpperCase();
    if (key != 'REPLAYGAIN_TRACK_GAIN') continue;
    return _parseGainValue(entry.substring(separator + 1));
  }
  return null;
}

int _leUint32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

int _syncSafe(Uint8List bytes, int offset) =>
    ((bytes[offset] & 0x7F) << 21) |
    ((bytes[offset + 1] & 0x7F) << 14) |
    ((bytes[offset + 2] & 0x7F) << 7) |
    (bytes[offset + 3] & 0x7F);

int _beUint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

double? _readId3v2(Uint8List bytes) {
  final major = bytes[3];
  final flags = bytes[5];
  final tagSize = _syncSafe(bytes, 6);
  var offset = 10;
  // 扩展头：v2.3/2.4 是 4 字节大小 + 若干标志位，直接跳过整段。
  if ((flags & 0x40) != 0 && offset + 4 <= bytes.length) {
    final extended = major >= 4
        ? _syncSafe(bytes, offset)
        : _beUint32(bytes, offset);
    offset += 4 + extended;
  }
  final end = math.min(bytes.length, 10 + tagSize);
  while (offset + 10 <= end) {
    final frameId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) break;
    final size = major >= 4
        ? _syncSafe(bytes, offset + 4)
        : _beUint32(bytes, offset + 4);
    final frameStart = offset + 10;
    if (size <= 0 || frameStart + size > end) break;
    if (frameId == 'TXXX') {
      final gain = _readTxxx(bytes, frameStart, size);
      if (gain != null) return gain;
    }
    offset = frameStart + size;
  }
  return null;
}

double? _readTxxx(Uint8List bytes, int start, int length) {
  if (length < 2) return null;
  final encoding = bytes[start];
  final body = bytes.sublist(start + 1, start + length);
  // 编码字节：0/3 为单字节（Latin-1/UTF-8），1/2 为 UTF-16。
  final separator = encoding == 1 || encoding == 2
      ? _indexOfUtf16Terminator(body)
      : body.indexOf(0);
  if (separator < 0) return null;
  final description = _decodeText(body.sublist(0, separator), encoding);
  if (description.toUpperCase() != 'REPLAYGAIN_TRACK_GAIN') return null;
  final valueStart = encoding == 1 || encoding == 2
      ? separator + 2
      : separator + 1;
  if (valueStart >= body.length) return null;
  final value = _decodeText(body.sublist(valueStart), encoding);
  return _parseGainValue(value);
}

int _indexOfUtf16Terminator(Uint8List bytes) {
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    if (bytes[i] == 0 && bytes[i + 1] == 0) return i;
  }
  return -1;
}

String _decodeText(Uint8List bytes, int encoding) {
  if (encoding == 1 || encoding == 2) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final unit = encoding == 1
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1];
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }
  return String.fromCharCodes(
    bytes.takeWhile((byte) => byte != 0).toList(growable: false),
  );
}
