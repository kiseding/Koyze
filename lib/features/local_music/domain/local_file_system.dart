import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// 本地音乐文件系统操作的跨平台抽象。
///
/// 各平台的「文件」不是同一个东西：
///
/// - Windows / Linux：普通路径，`dart:io` 直接读写。
/// - macOS：路径也是普通路径，但应用跑在 App Sandbox 里，只有用户显式
///   授权过的目录才可写（见 `files.user-selected.read-write` entitlement）。
/// - Android：目录是 SAF 的 `content://` 树，Dart 侧拿不到真实路径，所有
///   操作必须经 `ContentResolver` 转发。
/// - iOS：目录是 security-scoped URL，访问前要 `startAccessingSecurityScopedResource`。
/// - HarmonyOS：走 `@ohos.file.fs`，同样需要原生通道。
///
/// 因此这里只定义「能做什么」，具体怎么做由各平台实现决定。调用方不
/// 需要知道自己跑在哪个平台，也不需要判断路径长什么样。
abstract class LocalFileSystem {
  /// 当前平台是否支持文件管理。Web 恒为 false。
  bool get isSupported;

  /// 列出 [directoryPath] 下的直接子项。
  Future<List<LocalFileEntry>> listDirectory(String directoryPath);

  /// 把 [sourcePath] 复制到 [targetDirectory]，保持原文件名。
  ///
  /// 返回新文件的完整路径。目标已存在时抛 [LocalFileConflictException]，
  /// 由调用方决定改名还是覆盖。
  Future<String> copyInto(String sourcePath, String targetDirectory);

  /// 把 [sourcePath] 移动到 [targetDirectory]，保持原文件名。
  ///
  /// 与 [copyInto] 的差别只在是否保留源文件。实现上不保证是原子操作：
  /// Android SAF 没有 move API，只能是「复制成功后再删源」。
  Future<String> moveInto(String sourcePath, String targetDirectory);

  /// 重命名 [sourcePath] 为 [newName]（只改文件名，不换目录）。
  ///
  /// [newName] 是纯文件名，含扩展名。返回新路径。
  Future<String> rename(String sourcePath, String newName);

  /// 删除文件。目录不在此列——删目录的风险与语义都不同，单独处理。
  Future<void> deleteFile(String path);

  /// 在 [parentPath] 下创建目录。
  Future<String> createDirectory(String parentPath, String name);

  /// [path] 是否存在。
  Future<bool> exists(String path);

  /// 是否需要在原生侧选目录。
  ///
  /// 桌面 / Android / iOS 都用 `file_picker` 的目录选择器；只有鸿蒙不行
  /// ——它的 `file_picker` 移植把「选目录」实现成了「选文件后读进缓存」，
  /// 返回的压根不是目录。所以鸿蒙自己实现，由 UI 层按这个标志分派。
  bool get needsNativeDirectoryPicker => false;

  /// 让用户选一个目录。取消时返回 null。
  ///
  /// 只有 [needsNativeDirectoryPicker] 为真的平台会调到这里。
  Future<String?> pickDirectory() async => null;

  /// 按平台选择实现。
  ///
  /// [channel] 由调用方注入，方便测试替身；生产环境用默认的
  /// `koyze/local_file_system`。
  static LocalFileSystem forPlatform({
    MethodChannel? channel,
    LocalFileSystem? ioOverride,
  }) {
    if (ioOverride != null) return ioOverride;
    // Web 必须最先判：dart2js 下 `Platform.isAndroid` 等全是 false，
    // 不拦住会一路落到 IoFileSystem，然后每个操作在运行时才炸。
    if (kIsWeb) return const UnsupportedFileSystem();
    final platformChannel =
        channel ?? const MethodChannel('koyze/local_file_system');
    if (Platform.isAndroid) {
      return AndroidFileSystem(channel: platformChannel);
    }
    if (Platform.isIOS) {
      return AppleFileSystem(channel: platformChannel);
    }
    // 鸿蒙的 `Platform` 常量里没有 isOhos，只能比字符串。
    if (Platform.operatingSystem == 'ohos') {
      return OhosFileSystem(channel: platformChannel);
    }
    if (Platform.isMacOS) {
      // macOS 与桌面共用 dart:io，但沙盒下仍可能被拒——由实现层把
      // PathAccessException 转成 LocalFileAccessDeniedException。
      return const IoFileSystem(isSandboxed: true);
    }
    return const IoFileSystem();
  }
}

/// 目录里的一项。
class LocalFileEntry {
  const LocalFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modifiedAt,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modifiedAt;

  bool get isAudio => !isDirectory && isAudioFileName(name);
}

/// 判断文件名是不是音频。与扫描器保持一致，避免「列得出来但扫不到」。
bool isAudioFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return false;
  const audioExtensions = {
    'mp3',
    'flac',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wav',
    'aiff',
    'aif',
    'ape',
    'wma',
    'dsf',
    'dff',
    'alac',
  };
  return audioExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// 目标位置已经有同名文件。
class LocalFileConflictException implements Exception {
  const LocalFileConflictException(this.path);

  final String path;

  @override
  String toString() => '目标位置已存在同名文件: $path';
}

/// 系统拒绝了访问。常见于 macOS 沙盒未授权、iOS 书签失效。
class LocalFileAccessDeniedException implements Exception {
  const LocalFileAccessDeniedException(this.path, [this.cause]);

  final String path;
  final Object? cause;

  @override
  String toString() =>
      '没有权限访问 $path${cause == null ? '' : '（$cause）'}';
}

/// 操作本身不被当前平台支持。
class LocalFileUnsupportedException implements Exception {
  const LocalFileUnsupportedException(this.operation, this.platform, [this.cause]);

  final String operation;
  final String platform;
  final Object? cause;

  @override
  String toString() =>
      '$platform 上不支持 $operation${cause == null ? '' : '（$cause）'}';
}

/// 用 `dart:io` 实现的版本：Windows、Linux，以及沙盒内的 macOS。
class IoFileSystem implements LocalFileSystem {
  const IoFileSystem({this.isSandboxed = false});

  /// macOS 沙盒下要把权限错误翻译成 [LocalFileAccessDeniedException]，
  /// 否则上层只能拿到一个 `FileSystemException`，没法给出有用的提示。
  final bool isSandboxed;

  @override
  bool get isSupported => true;

  @override
  Future<List<LocalFileEntry>> listDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return const [];
    final entries = <LocalFileEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is Directory) {
        entries.add(
          LocalFileEntry(name: name, path: entity.path, isDirectory: true),
        );
      } else if (entity is File) {
        FileStat stat;
        try {
          stat = await entity.stat();
        } catch (_) {
          stat = FileStat.statSync(entity.path);
        }
        entries.add(
          LocalFileEntry(
            name: name,
            path: entity.path,
            isDirectory: false,
            size: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      }
    }
    entries.sort(_byDirectoryThenName);
    return entries;
  }

  @override
  Future<String> copyInto(String sourcePath, String targetDirectory) async {
    final name = _baseName(sourcePath);
    final target = _join(targetDirectory, name);
    if (await File(target).exists()) {
      throw LocalFileConflictException(target);
    }
    await _guard(targetDirectory, () async {
      await File(sourcePath).copy(target);
    });
    return target;
  }

  @override
  Future<String> moveInto(String sourcePath, String targetDirectory) async {
    final name = _baseName(sourcePath);
    final target = _join(targetDirectory, name);
    if (await File(target).exists()) {
      throw LocalFileConflictException(target);
    }
    await _guard(targetDirectory, () async {
      // 同一分区内 rename 是原子的，跨分区会抛跨设备错误，退回复制+删除。
      try {
        await File(sourcePath).rename(target);
      } on FileSystemException {
        await File(sourcePath).copy(target);
        await File(sourcePath).delete();
      }
    });
    return target;
  }

  @override
  Future<String> rename(String sourcePath, String newName) async {
    _validateFileName(newName);
    final parent = _parentOf(sourcePath);
    final target = _join(parent, newName);
    if (await File(target).exists()) {
      throw LocalFileConflictException(target);
    }
    await _guard(parent, () async {
      await File(sourcePath).rename(target);
    });
    return target;
  }

  @override
  Future<void> deleteFile(String path) async {
    await _guard(path, () async {
      final file = File(path);
      if (await file.exists()) await file.delete();
    });
  }

  @override
  Future<String> createDirectory(String parentPath, String name) async {
    _validateFileName(name);
    final target = _join(parentPath, name);
    await _guard(parentPath, () async {
      await Directory(target).create(recursive: false);
    });
    return target;
  }

  @override
  Future<bool> exists(String path) async {
    final type = await FileSystemEntity.type(path);
    return type != FileSystemEntityType.notFound;
  }

  @override
  bool get needsNativeDirectoryPicker => false;

  @override
  Future<String?> pickDirectory() async => null;

  Future<void> _guard(String path, Future<void> Function() action) async {
    try {
      await action();
    } on FileSystemException catch (error) {
      if (_isPermissionError(error)) {
        throw LocalFileAccessDeniedException(path, error);
      }
      rethrow;
    }
  }

  static bool _isPermissionError(FileSystemException error) {
    final code = error.osError?.errorCode;
    // Windows: 5 = ACCESS_DENIED, 32 = SHARING_VIOLATION
    // POSIX:   1 = EPERM, 13 = EACCES, 30 = EROFS
    return code == 5 || code == 32 || code == 1 || code == 13 || code == 30;
  }
}

/// Android / iOS / HarmonyOS 共用的原生通道实现。
///
/// 三个平台的原生侧各自不同（ContentResolver / security-scoped URL /
/// `@ohos.file.fs`），但**线上协议是同一套**：方法名、参数名、返回形态都对齐，
/// 所以解析逻辑只写一遍。想加平台就加个子类改 [isSupported] 和 [platformName]。
abstract class ChannelFileSystem implements LocalFileSystem {
  const ChannelFileSystem({required this.channel});

  final MethodChannel channel;

  /// 出错时拼消息用，例如「Android 上不支持…」。
  String get platformName;

  @override
  bool get isSupported => true;

  /// 桌面 / Android / iOS 都用 `file_picker` 的目录选择器。
  @override
  bool get needsNativeDirectoryPicker => false;

  @override
  Future<String?> pickDirectory() async => null;

  @override
  Future<List<LocalFileEntry>> listDirectory(String directoryPath) async {
    final raw = await _guard(
      directoryPath,
      () => channel.invokeMethod<List<dynamic>>('listDirectory', {
        'path': directoryPath,
      }),
    );
    final entries = (raw ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((entry) {
          final map = Map<String, dynamic>.from(entry);
          return LocalFileEntry(
            name: map['name']?.toString() ?? '',
            path: map['path']?.toString() ?? '',
            isDirectory: map['isDirectory'] == true,
            // 用 num 而不是 int：鸿蒙（ArkTS 编译到 JS）的数字默认是 double，
            // 严格判 int 会全部落空，界面上每个文件都显示 0 B。
            size: _asInt(map['size']) ?? 0,
            modifiedAt: switch (_asInt(map['modifiedAt'])) {
              null => null,
              final ms => DateTime.fromMillisecondsSinceEpoch(ms),
            },
          );
        })
        .toList(growable: false);
    return entries.toList()..sort(_byDirectoryThenName);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  @override
  Future<String> copyInto(String sourcePath, String targetDirectory) =>
      _invoke('copyInto', sourcePath, targetDirectory);

  @override
  Future<String> moveInto(String sourcePath, String targetDirectory) =>
      _invoke('moveInto', sourcePath, targetDirectory);

  @override
  Future<String> rename(String sourcePath, String newName) async {
    _validateFileName(newName);
    return _invoke('rename', sourcePath, newName);
  }

  @override
  Future<void> deleteFile(String path) async {
    await _guard(
      path,
      () => channel.invokeMethod<void>('deleteFile', {'path': path}),
    );
  }

  @override
  Future<String> createDirectory(String parentPath, String name) async {
    _validateFileName(name);
    return _invoke('createDirectory', parentPath, name);
  }

  @override
  Future<bool> exists(String path) async {
    // 显式给 T 是 bool?：原生侧可能返回 null（通道没实现这个方法），
    // 那要当成「不存在」而不是抛错。
    final found = await _guard<bool?>(
      path,
      () => channel.invokeMethod<bool>('exists', {'path': path}),
    );
    return found ?? false;
  }

  Future<String> _invoke(
    String method,
    String source,
    String target,
  ) async {
    final result = await _guard(
      source,
      () => channel.invokeMethod<String>(method, {
        'source': source,
        'target': target,
      }),
    );
    if (result == null) {
      throw LocalFileAccessDeniedException(source);
    }
    return result;
  }

  /// 把原生抛回来的错误码翻译成类型化异常。
  ///
  /// 不翻译的话上层只能拿到一个 `PlatformException`，UI 既没法判断「是重名
  /// 还是没权限」，也没法给用户可操作的提示。原生侧的码值在三端保持一致：
  /// `conflict` / `access_denied` / `not_found`。
  Future<T> _guard<T>(String path, Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      switch (error.code) {
        case 'conflict':
          throw LocalFileConflictException(path);
        case 'access_denied':
          throw LocalFileAccessDeniedException(path, error.message);
        default:
          rethrow;
      }
    } on MissingPluginException catch (error) {
      // 原生侧没注册通道：多半是这个平台的构建漏了实现。
      throw LocalFileUnsupportedException('文件操作', platformName, error);
    }
  }
}

/// Android：路径分两种，必须分开处理。
///
/// - **应用私有目录**（`/data/user/0/...`，也就是下载目录所在的
///   `getApplicationDocumentsDirectory()`）：`dart:io` 完全可用，不需要
///   任何权限。这是本功能的主场景——用户要把下载好的歌从私有目录搬出去。
/// - **SAF 授权树**（`content://` 或 `content://koyze/...`）：Dart 侧拿不到
///   真实路径，必须经 `ContentResolver`。
///
/// 之前一律走 SAF，结果主场景直接失败：私有目录不在任何 SAF 树里，
/// `resolveDocumentId` 解析不出来，所有操作都返回「没权限」。
class AndroidFileSystem implements LocalFileSystem {
  AndroidFileSystem({required this.channel});

  final MethodChannel channel;

  /// 私有目录用 dart:io，其余交给原生。
  ///
  /// 判据是「是不是 `content://`」。`getApplicationDocumentsDirectory()`
  /// 返回的是 `/data/user/0/<pkg>/app_flutter`，普通路径；而用户通过
  /// `ACTION_OPEN_DOCUMENT_TREE` 授权的目录一定是 `content://`。
  final _io = const IoFileSystem();

  /// 本机私有目录根。用于识别 `content://koyze/...` 之外的普通路径。
  bool _isDocumentPath(String path) =>
      path.startsWith('content://') || path.startsWith('koyze://');

  @override
  bool get isSupported => true;

  /// Android 用系统 SAF 选择器（`file_picker` 的 `dir` 走
  /// `ACTION_OPEN_DOCUMENT_TREE`），不需要自建选择器。
  @override
  bool get needsNativeDirectoryPicker => false;

  @override
  Future<String?> pickDirectory() async => null;

  @override
  Future<List<LocalFileEntry>> listDirectory(String directoryPath) {
    if (_isDocumentPath(directoryPath)) {
      return _saf.listDirectory(directoryPath);
    }
    return _io.listDirectory(directoryPath);
  }

  @override
  Future<String> copyInto(String sourcePath, String targetDirectory) {
    // 源和目标是同一种「世界」才能直接转发；混着来（私有目录 → SAF）
    // 只能由原生侧做流式复制，因为 Dart 侧读不到 content:// 的字节。
    if (_isDocumentPath(sourcePath) && _isDocumentPath(targetDirectory)) {
      return _saf.copyInto(sourcePath, targetDirectory);
    }
    if (!_isDocumentPath(sourcePath) && !_isDocumentPath(targetDirectory)) {
      return _io.copyInto(sourcePath, targetDirectory);
    }
    return _crossCopy(sourcePath, targetDirectory, move: false);
  }

  @override
  Future<String> moveInto(String sourcePath, String targetDirectory) {
    if (_isDocumentPath(sourcePath) && _isDocumentPath(targetDirectory)) {
      return _saf.moveInto(sourcePath, targetDirectory);
    }
    if (!_isDocumentPath(sourcePath) && !_isDocumentPath(targetDirectory)) {
      return _io.moveInto(sourcePath, targetDirectory);
    }
    return _crossCopy(sourcePath, targetDirectory, move: true);
  }

  @override
  Future<String> rename(String sourcePath, String newName) {
    if (_isDocumentPath(sourcePath)) return _saf.rename(sourcePath, newName);
    return _io.rename(sourcePath, newName);
  }

  @override
  Future<void> deleteFile(String path) {
    if (_isDocumentPath(path)) return _saf.deleteFile(path);
    return _io.deleteFile(path);
  }

  @override
  Future<String> createDirectory(String parentPath, String name) {
    if (_isDocumentPath(parentPath)) {
      return _saf.createDirectory(parentPath, name);
    }
    return _io.createDirectory(parentPath, name);
  }

  @override
  Future<bool> exists(String path) {
    if (_isDocumentPath(path)) return _saf.exists(path);
    return _io.exists(path);
  }

  AndroidSafFileSystem get _saf => AndroidSafFileSystem(channel: channel);

  /// 跨越私有目录与 SAF 树。
  ///
  /// 这一路必须交给原生：Dart 的 `File` 打不开 `content://`，而原生侧
  /// 两条路都能读，所以统一由 `SafFileAccess` 做流式中转。
  Future<String> _crossCopy(
    String sourcePath,
    String targetDirectory, {
    required bool move,
  }) async {
    try {
      final result = await channel.invokeMethod<String>(
        move ? 'moveAcross' : 'copyAcross',
        {'source': sourcePath, 'target': targetDirectory},
      );
      if (result == null) {
        throw LocalFileAccessDeniedException(sourcePath);
      }
      return result;
    } on PlatformException catch (error) {
      if (error.code == 'conflict') {
        throw LocalFileConflictException(targetDirectory);
      }
      if (error.code == 'access_denied') {
        throw LocalFileAccessDeniedException(sourcePath, error.message);
      }
      rethrow;
    }
  }
}

/// Android SAF 授权树：所有操作经 `ContentResolver` 转发到原生侧。
class AndroidSafFileSystem extends ChannelFileSystem {
  const AndroidSafFileSystem({required super.channel});

  @override
  String get platformName => 'Android';
}

/// iOS：目录是 security-scoped URL，必须经原生侧 startAccessing。
class AppleFileSystem extends ChannelFileSystem {
  const AppleFileSystem({required super.channel});

  @override
  String get platformName => 'iOS';
}

/// HarmonyOS：原生侧用 `@ohos.file.fs`，路径是普通路径或 `file://docs/...`。
class OhosFileSystem extends ChannelFileSystem {
  const OhosFileSystem({required super.channel});

  @override
  String get platformName => 'HarmonyOS';

  @override
  bool get needsNativeDirectoryPicker => true;

  @override
  Future<String?> pickDirectory() async {
    final path = await channel.invokeMethod<String>('pickDirectory');
    // 原生侧用空串表示「用户取消」，这里翻成 null 与其它平台一致。
    if (path == null || path.isEmpty) return null;
    return path;
  }
}

/// Web：浏览器里没有可写的文件系统。
class UnsupportedFileSystem implements LocalFileSystem {
  const UnsupportedFileSystem();

  @override
  bool get isSupported => false;

  @override
  bool get needsNativeDirectoryPicker => false;

  @override
  Future<String?> pickDirectory() async => null;

  Never _reject(String operation) => throw LocalFileUnsupportedException(
    operation,
    'Web',
  );

  @override
  Future<List<LocalFileEntry>> listDirectory(String directoryPath) async =>
      _reject('列出目录');

  @override
  Future<String> copyInto(String sourcePath, String targetDirectory) async =>
      _reject('复制文件');

  @override
  Future<String> moveInto(String sourcePath, String targetDirectory) async =>
      _reject('移动文件');

  @override
  Future<String> rename(String sourcePath, String newName) async =>
      _reject('重命名');

  @override
  Future<void> deleteFile(String path) async => _reject('删除文件');

  @override
  Future<String> createDirectory(String parentPath, String name) async =>
      _reject('新建文件夹');

  @override
  Future<bool> exists(String path) async => false;
}

int _byDirectoryThenName(LocalFileEntry a, LocalFileEntry b) {
  if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

String _baseName(String path) {
  final cut = _lastSeparatorIndex(path);
  return cut < 0 ? path : path.substring(cut + 1);
}

String _parentOf(String path) {
  final cut = _lastSeparatorIndex(path);
  if (cut < 0) return path;
  // 根目录本身：'/a' 的父目录是 '/'，别退化成空串。
  if (cut == 0) return path.substring(0, 1);
  // Windows 盘符根：'C:/a' 的父目录是 'C:/'，丢掉斜杠会变成相对路径 'C:'。
  if (cut == 2 && path[1] == ':') return path.substring(0, 3);
  return path.substring(0, cut);
}

/// 找最后一个分隔符的位置，`/` 和 `\` 都算。
///
/// 这里刻意**不**先把 `\` 归一成 `/` 再切：切完还要拼回去，归一化会让
/// Windows 路径变成 `C:/a\b` 这种混合形式。文件 API 认，但和 `Directory.list`
/// 返回的路径对不上，UI 里按路径比较或去重就会失效。
int _lastSeparatorIndex(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  return slash > backslash ? slash : backslash;
}

String _join(String directory, String name) {
  final separator = Platform.pathSeparator;
  // 只去掉**多余**的尾分隔符：'/' 和 'C:/' 本身就是根，剥掉会变成相对路径。
  final isRoot = directory == '/' || directory == r'\' || _isDriveRoot(directory);
  final trimmed = isRoot || directory.isEmpty
      ? directory
      : (directory.endsWith('/') || directory.endsWith(r'\')
            ? directory.substring(0, directory.length - 1)
            : directory);
  return '$trimmed$separator$name';
}

bool _isDriveRoot(String path) =>
    path.length == 3 && path[1] == ':' && (path[2] == '/' || path[2] == r'\');

/// 拒绝 `..`、路径分隔符和空名字，避免重命名把文件挪到别的目录。
void _validateFileName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(name, 'name', '文件名不能为空');
  }
  if (trimmed.contains('/') || trimmed.contains(r'\')) {
    throw ArgumentError.value(name, 'name', '文件名不能包含路径分隔符');
  }
  if (trimmed == '.' || trimmed == '..') {
    throw ArgumentError.value(name, 'name', '文件名不合法');
  }
}
