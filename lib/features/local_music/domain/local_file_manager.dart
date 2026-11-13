import 'package:koyze/features/local_music/domain/local_file_system.dart';
import 'package:koyze/features/local_music/domain/local_music_debug_log.dart';

/// 一次文件操作的种类。
enum LocalFileOperation { copy, move, rename, delete, createDirectory }

/// 单个文件的操作结果。
class LocalFileResult {
  const LocalFileResult({
    required this.operation,
    required this.sourcePath,
    this.targetPath,
    this.error,
  });

  final LocalFileOperation operation;
  final String sourcePath;
  final String? targetPath;
  final Object? error;

  bool get succeeded => error == null;
}

/// 一批操作的汇总。
class LocalFileBatchResult {
  const LocalFileBatchResult(this.results);

  final List<LocalFileResult> results;

  int get succeeded => results.where((r) => r.succeeded).length;
  int get failed => results.length - succeeded;
  bool get allSucceeded => failed == 0;

  List<LocalFileResult> get failures =>
      results.where((r) => !r.succeeded).toList(growable: false);
}

/// 本地音乐的文件搬运层。
///
/// 只做一件事：把文件从 A 弄到 B。**不碰曲库索引**。
///
/// 这是刻意的。这个功能的目的不是「整理曲库」，而是「把应用私有目录里的
/// 文件搬到一个在系统文件管理器里看得到的地方」——移动端应用的数据目录
/// 对外不可见，导出一首歌过去得靠分享或文件选择器，批量搬就很不方便。
///
/// 所以搬走之后曲库扫不到它，是**正确结果**而不是需要修补的副作用：
/// 用户就是要把文件挪出扫描范围。索引由下一次重扫自然收敛——`rescanAll`
/// 会把不在磁盘上的条目当成 stale 剔掉。
///
/// 反过来，如果在搬文件时同步改索引，就变成「移出扫描目录后曲库还显示
/// 这首歌，点了却播不了」，那才是 bug。
class LocalFileManager {
  LocalFileManager({
    required LocalFileSystem fileSystem,
    // ignore: prefer_initializing_formals
  }) : _fileSystem = fileSystem;

  final LocalFileSystem _fileSystem;

  LocalFileSystem get fileSystem => _fileSystem;

  bool get isSupported => _fileSystem.isSupported;

  /// 列目录。不支持文件管理的平台返回空列表。
  Future<List<LocalFileEntry>> list(String directoryPath) {
    if (!_fileSystem.isSupported) return Future.value(const []);
    return _fileSystem.listDirectory(directoryPath);
  }

  /// 批量复制到 [targetDirectory]。
  Future<LocalFileBatchResult> copy(
    Iterable<String> sourcePaths,
    String targetDirectory,
  ) => _runBatch(
    LocalFileOperation.copy,
    sourcePaths,
    (path) => _fileSystem.copyInto(path, targetDirectory),
  );

  /// 批量移动到 [targetDirectory]。
  Future<LocalFileBatchResult> move(
    Iterable<String> sourcePaths,
    String targetDirectory,
  ) => _runBatch(
    LocalFileOperation.move,
    sourcePaths,
    (path) => _fileSystem.moveInto(path, targetDirectory),
  );

  /// 重命名单个文件。[newName] 是纯文件名（含扩展名）。
  Future<LocalFileResult> rename(String sourcePath, String newName) async {
    try {
      final target = await _fileSystem.rename(sourcePath, newName);
      return LocalFileResult(
        operation: LocalFileOperation.rename,
        sourcePath: sourcePath,
        targetPath: target,
      );
    } catch (error, stackTrace) {
      LocalMusicDebugLog.error(
        'file_manager.rename.failed',
        'path=${LocalMusicDebugLog.quote(sourcePath)} name=$newName error=$error',
        stackTrace: stackTrace,
      );
      return LocalFileResult(
        operation: LocalFileOperation.rename,
        sourcePath: sourcePath,
        error: error,
      );
    }
  }

  /// 批量删除。删除不可逆，UI 层必须先做强确认。
  Future<LocalFileBatchResult> delete(Iterable<String> paths) => _runBatch(
    LocalFileOperation.delete,
    paths,
    (path) async {
      await _fileSystem.deleteFile(path);
      return null;
    },
  );

  /// 在 [parentPath] 下建目录。
  Future<LocalFileResult> createDirectory(String parentPath, String name) async {
    try {
      final target = await _fileSystem.createDirectory(parentPath, name);
      return LocalFileResult(
        operation: LocalFileOperation.createDirectory,
        sourcePath: parentPath,
        targetPath: target,
      );
    } catch (error) {
      return LocalFileResult(
        operation: LocalFileOperation.createDirectory,
        sourcePath: parentPath,
        error: error,
      );
    }
  }

  Future<LocalFileBatchResult> _runBatch(
    LocalFileOperation operation,
    Iterable<String> paths,
    Future<String?> Function(String path) action,
  ) async {
    final results = <LocalFileResult>[];
    for (final path in paths) {
      try {
        final target = await action(path);
        results.add(
          LocalFileResult(
            operation: operation,
            sourcePath: path,
            targetPath: target,
          ),
        );
      } catch (error, stackTrace) {
        LocalMusicDebugLog.error(
          'file_manager.${operation.name}.failed',
          'path=${LocalMusicDebugLog.quote(path)} error=$error',
          stackTrace: stackTrace,
        );
        // 单个文件失败不中断整批：用户选了 20 首，其中 1 首被占用，
        // 剩下 19 首应该照常处理。
        results.add(
          LocalFileResult(
            operation: operation,
            sourcePath: path,
            error: error,
          ),
        );
      }
    }
    return LocalFileBatchResult(results);
  }
}
