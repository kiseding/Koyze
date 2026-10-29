import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 同名侧车歌词的候选后缀，按优先级排列。
///
/// 大小写都列出来是因为 Android 的 `/sdcard` 常见 exFAT/FAT32，那些分区
/// 大小写不敏感；而 Linux 桌面上的 ext4 是敏感的，用户的文件可能叫
/// `song.LRC`。直接挨个试比先 `listSync` 整个目录便宜得多。
const kSidecarLyricExtensions = <String>[
  'lrc',
  'LRC',
  'Lrc',
  'txt',
  'TXT',
];

/// 读取本地音频同目录下的同名歌词文件。
///
/// 本地音乐用户习惯把 `song.lrc` 放在 `song.flac` 旁边，而标签里往往没有
/// 内嵌歌词。这里只在元数据没带歌词时补位，并且永远不抛异常——读不到就是
/// 没有歌词，不该让播放页显示一个加载失败。
Future<String?> readSidecarLyric(String audioPath) async {
  final stem = _stemOf(audioPath);
  if (stem == null) return null;
  for (final extension in kSidecarLyricExtensions) {
    final file = File('$stem.$extension');
    try {
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      final text = decodeLyricBytes(bytes);
      if (text.trim().isEmpty) continue;
      // `.txt` 太泛：同目录的 readme.txt / 说明.txt 会被误当成歌词。
      // 只接受明显是歌词的内容（有时间轴，或至少有多行）。
      if (extension.toLowerCase() == 'txt' && !looksLikeLyric(text)) continue;
      return text;
    } catch (_) {
      // 权限不足 / 文件被占用 / 分存存储读不到：换下一个后缀继续试。
    }
  }
  return null;
}

/// 去掉扩展名，保留目录。没有扩展名时返回 null。
String? _stemOf(String path) {
  if (path.isEmpty) return null;
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final separator = slash > backslash ? slash : backslash;
  if (dot <= separator + 1) return null;
  return path.substring(0, dot);
}

/// 解码歌词字节。
///
/// 中文 LRC 有相当比例是 GBK，Dart 没有内置 GBK 解码表，硬塞一份码表会白白
/// 多出几十 KB。这里的取舍是：UTF-8 / UTF-16（带 BOM）正确解码，其余按
/// Latin-1 兜底——至少不会抛异常，用户看到的是乱码而不是「歌词加载失败」。
String decodeLyricBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
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

final _timeTag = RegExp(r'\[\d{1,2}:\d{2}([.:]\d{1,3})?\]');

/// 判断一段文本像不像歌词：有时间轴，或者至少两行非空。
bool looksLikeLyric(String text) {
  if (_timeTag.hasMatch(text)) return true;
  final lines = text
      .split(RegExp(r'\r\n|\r|\n'))
      .where((line) => line.trim().isNotEmpty)
      .length;
  return lines >= 2;
}
