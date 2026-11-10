// 文件说明：歌词自定义字体——格式校验、落盘安装、运行时注册。
//
// 这些逻辑单独放在 domain 里，是因为它和「设置页长什么样」无关：换一个 UI
// 仍然要按同样的规则判断「这个文件到底能不能当歌词字体」。测试也只需要喂
// 字节进来，不用起 widget。

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 允许的字体扩展名。
///
/// Flutter 的字体引擎只认 TrueType / OpenType 轮廓：
/// * `woff` / `woff2` 是网页封装（压缩 + 自定义表头），引擎不认；
/// * `ttc` 是字体集合，一个文件里塞多套字，`FontLoader` 不指定索引时行为
///   未定义，用户选到的大概率不是自己看到的那一套。
///
/// 与其让用户选完再报错，不如在文件选择器里就过滤掉，校验函数再兜一次底：
/// 部分桌面平台的扩展名过滤可以绕过（输入 `*.*`）。
const Set<String> kLyricFontExtensions = <String>{'ttf', 'otf'};

/// 单个字体文件上限。中文字体动辄 20MB，64MB 之内都算正常；再大基本是
/// 打错包的全家桶，读进内存也只是白占。
const int kLyricFontMaxBytes = 64 * 1024 * 1024;

/// 字体文件不能用的原因。UI 按这个枚举取文案，不直接展示字符串。
enum LyricFontIssue {
  /// 扩展名不在 [kLyricFontExtensions] 里。
  unsupportedFormat,

  /// 超过 [kLyricFontMaxBytes]。
  tooLarge,

  /// 空文件。
  emptyFile,

  /// 扩展名对，但内容不是字体（或是不支持的集合）。
  invalidData,

  /// 拿不到文件路径（Web 等没有本地文件系统的平台）。
  unavailablePath,

  /// 字体注册到引擎时失败。
  loadFailed,
}

class LyricFontException implements Exception {
  const LyricFontException(this.issue, {this.detail});

  final LyricFontIssue issue;
  final String? detail;

  @override
  String toString() =>
      'LyricFontException(${issue.name}${detail == null ? '' : ': $detail'})';
}

/// 一次成功安装的结果。
class LyricFontFile {
  const LyricFontFile({
    required this.path,
    required this.family,
    required this.displayName,
  });

  /// 应用私有目录里的副本。原文件被用户删掉/移动也不影响。
  final String path;

  /// 注册到引擎的字体族名。每个文件内容一个，避免重复注册同一族名。
  final String family;

  /// 给用户看的原始文件名。
  final String displayName;

  Map<String, String> toJson() => {
    'path': path,
    'family': family,
    'name': displayName,
  };
}

/// 小写扩展名（不带点）。没有扩展名时返回 null。
String? lyricFontExtensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return fileName.substring(dot + 1).toLowerCase();
}

bool isSupportedLyricFontName(String fileName) {
  final extension = lyricFontExtensionOf(fileName);
  return extension != null && kLyricFontExtensions.contains(extension);
}

/// 按文件头判断这是不是一套能直接注册的单体字体。
///
/// 只看扩展名不够：把 PNG 改名成 `.ttf` 一样能选进来，引擎那边只会报一个
/// 没有上下文的错误码。这里按 sfnt 的 magic number 提前拦掉大部分情况。
bool looksLikeFontBytes(Uint8List bytes) {
  if (bytes.length < 12) return false;
  final tag = String.fromCharCodes(bytes.sublist(0, 4));
  // 集合：一个文件多套字，不支持。
  if (tag == 'ttcf') return false;
  if (tag == 'OTTO' || tag == 'true' || tag == 'typ1') return true;
  final version = ByteData.sublistView(bytes, 0, 4).getUint32(0);
  return version == 0x00010000;
}

/// 校验文件本身，不碰磁盘。不合法时抛 [LyricFontException]。
void validateLyricFont({required String fileName, required Uint8List bytes}) {
  if (!isSupportedLyricFontName(fileName)) {
    throw const LyricFontException(LyricFontIssue.unsupportedFormat);
  }
  if (bytes.isEmpty) {
    throw const LyricFontException(LyricFontIssue.emptyFile);
  }
  if (bytes.length > kLyricFontMaxBytes) {
    throw const LyricFontException(LyricFontIssue.tooLarge);
  }
  if (!looksLikeFontBytes(bytes)) {
    throw const LyricFontException(LyricFontIssue.invalidData);
  }
}

/// 字体族名：用内容哈希，同一份文件永远同一个名字。
///
/// 不用固定族名（例如 `KoyzeLyricFont`）是因为 `FontLoader` 对同一个族名
/// 重复注册的行为没有保证；用内容哈希后，换字体天然是换族名，旧的那套
/// 自然被新引用取代。
String lyricFontFamilyFor(List<int> bytes) {
  final digest = sha1.convert(bytes).toString();
  return 'KoyzeLyric-${digest.substring(0, 16)}';
}

/// 把字体注册到引擎。同一个族名只应该调用一次。
Future<void> registerLyricFontFamily(String family, Uint8List bytes) async {
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// 校验 → 复制到应用目录 → 注册。返回可持久化的 [LyricFontFile]。
///
/// 复制而不是直接引用原路径：桌面端用户可能把字体放在下载目录，清一次就
/// 没了；移动端 `file_picker` 给的还是缓存副本，系统随时会回收。
Future<LyricFontFile> installLyricFont({
  required String fileName,
  required Uint8List bytes,
}) async {
  validateLyricFont(fileName: fileName, bytes: bytes);

  final support = await getApplicationSupportDirectory();
  final directory = Directory('${support.path}/lyric_fonts');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  final family = lyricFontFamilyFor(bytes);
  final extension = lyricFontExtensionOf(fileName) ?? 'ttf';
  final file = File('${directory.path}/${family.substring(12)}.$extension');
  if (!await file.exists()) {
    await file.writeAsBytes(bytes, flush: true);
  }

  try {
    await registerLyricFontFamily(family, bytes);
  } on Object catch (error) {
    throw LyricFontException(LyricFontIssue.loadFailed, detail: '$error');
  }

  // 只留当前这一套。用户可能反复试字体，不清理的话每试一次就多几十兆。
  await _pruneFonts(directory, keep: file.path);

  return LyricFontFile(path: file.path, family: family, displayName: fileName);
}

/// 启动时恢复：从磁盘读回上次安装的字体并注册。
Future<LyricFontFile?> restoreLyricFont({
  required String path,
  required String displayName,
  required String family,
}) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (!looksLikeFontBytes(bytes)) return null;
    await registerLyricFontFamily(family, bytes);
    return LyricFontFile(path: path, family: family, displayName: displayName);
  } on Object {
    return null;
  }
}

Future<void> _pruneFonts(Directory directory, {required String keep}) async {
  try {
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (entity.path == keep) continue;
      await entity.delete();
    }
  } on Object {
    // 清理失败不影响字体本身可用。
  }
}
