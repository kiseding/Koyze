/// M3U / M3U8 歌单的读写。
///
/// 这是音乐库之间唯一事实通用的歌单格式：foobar2000、VLC、AIMP、各种车机
/// 都能读。用 UTF-8 写出来就是 M3U8，没必要单独处理扩展名差异。
library;

import 'dart:convert';
import 'dart:typed_data';

class M3uEntry {
  const M3uEntry({
    required this.location,
    this.title,
    this.artist,
    this.duration,
  });

  /// 绝对路径或 URL。相对路径在解析时已按清单所在目录展开。
  final String location;
  final String? title;
  final String? artist;

  /// 直播流是 null（`#EXTINF:-1`）。
  final Duration? duration;

  /// `#EXTINF` 里冒号后面那一段：`245,周杰伦 - 晴天`。
  String get extinf {
    final seconds = duration?.inSeconds ?? -1;
    final name = [artist, title].whereType<String>().where((s) => s.isNotEmpty);
    final label = name.isEmpty ? location : name.join(' - ');
    return '#EXTINF:$seconds,$label';
  }
}

class M3uDocument {
  const M3uDocument({required this.entries, required this.droppedLines});

  final List<M3uEntry> entries;

  /// 形如 `#EXTINF` 但没有对应路径的悬空行数量。用于在导入结果里告知用户
  /// 「这个文件有 3 条记录是坏的」，而不是默默少几首。
  final int droppedLines;
}

/// 解码 M3U 文件字节。
///
/// 路径本身几乎都是 ASCII，会乱码的只有标题。带 BOM 的按 BOM 走；没有 BOM
/// 时先试 UTF-8（现代播放器的默认），失败再按 Latin-1 兜底——GBK 清单里的
/// 中文会变成乱码，但路径依然可用于匹配。
String decodeM3uBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes.sublist(2), littleEndian: false);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

String _utf16(Uint8List bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

final _extensionInfo = RegExp(r'^#EXTINF:\s*(-?\d+(?:\.\d+)?)\s*,(.*)$');
final _blankOrComment = RegExp(r'^\s*(#|$)');

/// 解析 M3U 内容。
///
/// [baseDirectory] 用于把相对路径展开成绝对路径——清单和音乐放在同一个
/// 文件夹里是常见做法，不展开的话后面永远匹配不上。
M3uDocument parseM3u(String content, {String? baseDirectory}) {
  final entries = <M3uEntry>[];
  var dropped = 0;

  // 待配对的 EXTINF 元信息。遇到下一个路径行就消费掉。
  String? pendingTitle;
  String? pendingArtist;
  Duration? pendingDuration;
  var hasPending = false;

  for (final rawLine in content.split(RegExp(r'\r\n|\r|\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line == '#EXTM3U') continue;

    final info = _extensionInfo.firstMatch(line);
    if (info != null) {
      // 连续两条 EXTINF 说明前一条没有路径，算坏记录。
      if (hasPending) dropped++;
      final seconds = double.tryParse(info.group(1)!);
      pendingDuration = (seconds == null || seconds < 0)
          ? null
          : Duration(seconds: seconds.round());
      final label = info.group(2)!.trim();
      final split = _splitArtistTitle(label);
      pendingArtist = split.$1;
      pendingTitle = split.$2;
      hasPending = true;
      continue;
    }

    if (_blankOrComment.hasMatch(line)) {
      // 其它指令（#EXTVLCOPT、#PLAYLIST 等）忽略，但不算坏记录。
      continue;
    }

    entries.add(
      M3uEntry(
        location: _resolveLocation(line, baseDirectory),
        title: pendingTitle,
        artist: pendingArtist,
        duration: pendingDuration,
      ),
    );
    pendingTitle = null;
    pendingArtist = null;
    pendingDuration = null;
    hasPending = false;
  }

  if (hasPending) dropped++;
  return M3uDocument(entries: entries, droppedLines: dropped);
}

/// 生成 M3U 文本（UTF-8 写盘即 M3U8）。
String buildM3u(Iterable<M3uEntry> entries) {
  final buffer = StringBuffer('#EXTM3U\n');
  for (final entry in entries) {
    buffer
      ..writeln(entry.extinf)
      ..writeln(entry.location);
  }
  return buffer.toString();
}

/// `周杰伦 - 晴天` → (周杰伦, 晴天)；没有分隔符时整段当标题。
(String?, String) _splitArtistTitle(String label) {
  if (label.isEmpty) return (null, '');
  // 只用「 - 」（两侧带空格）拆：歌名本身带连字符的情况远多于歌手名带。
  final separator = label.indexOf(' - ');
  if (separator <= 0 || separator >= label.length - 3) return (null, label);
  return (
    label.substring(0, separator).trim(),
    label.substring(separator + 3).trim(),
  );
}

String _resolveLocation(String location, String? baseDirectory) {
  if (baseDirectory == null || baseDirectory.isEmpty) return location;
  // URL 和已经是绝对路径的（含盘符或根斜杠）不需要展开。
  if (location.contains('://')) return location;
  if (location.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(location)) {
    return location;
  }
  final separator = baseDirectory.endsWith('/') ||
          baseDirectory.endsWith(r'\')
      ? ''
      : '/';
  return '$baseDirectory$separator$location';
}
