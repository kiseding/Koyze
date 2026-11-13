import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/local_music/domain/local_file_manager.dart';
import 'package:koyze/features/local_music/domain/local_file_system.dart';

/// 可编程替身：把「第几个文件失败」变成可控输入。
///
/// 批量操作的核心契约是「单个失败不中断整批」，只有能让指定路径抛错才能
/// 验证这一点，所以不直接拿真文件系统跑。
class _FakeFileSystem implements LocalFileSystem {
  _FakeFileSystem({Set<String> failOn = const {}, this.supported = true})
    : failOn = {...failOn};

  /// 命中这些路径时抛出 [error]。故意做成可变的，测试可以在中途改变
  /// 「谁会失败」，不必为每个场景重造替身。
  final Set<String> failOn;
  final bool supported;
  Object error = const FileSystemException('boom');

  final List<String> calls = [];

  @override
  bool get isSupported => supported;

  @override
  Future<List<LocalFileEntry>> listDirectory(String directoryPath) async {
    if (!supported) return const [];
    return [
      const LocalFileEntry(
        name: 'b.mp3',
        path: '/src/b.mp3',
        isDirectory: false,
        size: 20,
      ),
      const LocalFileEntry(name: 'sub', path: '/src/sub', isDirectory: true),
      const LocalFileEntry(
        name: 'a.flac',
        path: '/src/a.flac',
        isDirectory: false,
        size: 10,
      ),
      const LocalFileEntry(name: 'cover.jpg', path: '/src/cover.jpg',
          isDirectory: false, size: 5),
    ];
  }

  Future<String> _run(String op, String source, String target) async {
    calls.add('$op:$source');
    if (failOn.contains(source)) throw error;
    return '$target/${source.split('/').last}';
  }

  @override
  Future<String> copyInto(String sourcePath, String targetDirectory) =>
      _run('copy', sourcePath, targetDirectory);

  @override
  Future<String> moveInto(String sourcePath, String targetDirectory) =>
      _run('move', sourcePath, targetDirectory);

  @override
  Future<String> rename(String sourcePath, String newName) async {
    calls.add('rename:$sourcePath');
    if (failOn.contains(sourcePath)) throw error;
    final parent = sourcePath.substring(0, sourcePath.lastIndexOf('/'));
    return '$parent/$newName';
  }

  @override
  Future<void> deleteFile(String path) async {
    calls.add('delete:$path');
    if (failOn.contains(path)) throw error;
  }

  @override
  Future<String> createDirectory(String parentPath, String name) async {
    calls.add('mkdir:$parentPath');
    if (failOn.contains(parentPath)) throw error;
    return '$parentPath/$name';
  }

  @override
  Future<bool> exists(String path) async => true;

  @override
  bool get needsNativeDirectoryPicker => false;

  @override
  Future<String?> pickDirectory() async => null;
}

void main() {
  group('isAudioFileName', () {
    test('识别常见音频扩展名，大小写不敏感', () {
      expect(isAudioFileName('song.mp3'), isTrue);
      expect(isAudioFileName('song.FLAC'), isTrue);
      expect(isAudioFileName('song.M4a'), isTrue);
      expect(isAudioFileName('song.opus'), isTrue);
      expect(isAudioFileName('song.dsf'), isTrue);
    });

    test('封面图和文本不算音频', () {
      expect(isAudioFileName('cover.jpg'), isFalse);
      expect(isAudioFileName('notes.txt'), isFalse);
      expect(isAudioFileName('playlist.m3u'), isFalse);
    });

    test('没有扩展名或点号开头的不算', () {
      expect(isAudioFileName('mp3'), isFalse);
      expect(isAudioFileName('.mp3'), isFalse);
      expect(isAudioFileName('song.'), isFalse);
    });
  });

  group('LocalFileBatchResult 汇总', () {
    test('全部成功时 allSucceeded 为真且没有失败项', () {
      const result = LocalFileBatchResult([
        LocalFileResult(
          operation: LocalFileOperation.copy,
          sourcePath: '/a.mp3',
          targetPath: '/dst/a.mp3',
        ),
        LocalFileResult(
          operation: LocalFileOperation.copy,
          sourcePath: '/b.mp3',
          targetPath: '/dst/b.mp3',
        ),
      ]);

      expect(result.succeeded, 2);
      expect(result.failed, 0);
      expect(result.allSucceeded, isTrue);
      expect(result.failures, isEmpty);
    });

    test('部分失败时计数分开，failures 只留失败项', () {
      const result = LocalFileBatchResult([
        LocalFileResult(
          operation: LocalFileOperation.move,
          sourcePath: '/ok.mp3',
          targetPath: '/dst/ok.mp3',
        ),
        LocalFileResult(
          operation: LocalFileOperation.move,
          sourcePath: '/bad.mp3',
          error: 'denied',
        ),
      ]);

      expect(result.succeeded, 1);
      expect(result.failed, 1);
      expect(result.allSucceeded, isFalse);
      expect(result.failures.single.sourcePath, '/bad.mp3');
    });

    test('空批次算全成功——没选中任何文件不该报错', () {
      const result = LocalFileBatchResult([]);
      expect(result.allSucceeded, isTrue);
      expect(result.failed, 0);
    });
  });

  group('LocalFileManager 批量操作', () {
    test('单文件失败不中断整批，其余照常处理', () async {
      final fs = _FakeFileSystem(failOn: {'/src/b.mp3'});
      final manager = LocalFileManager(fileSystem: fs);

      final result = await manager.copy(
        ['/src/a.flac', '/src/b.mp3', '/src/c.mp3'],
        '/dst',
      );

      expect(result.succeeded, 2);
      expect(result.failed, 1);
      expect(result.failures.single.sourcePath, '/src/b.mp3');
      // 关键：失败之后仍继续处理了 c.mp3。
      expect(fs.calls, [
        'copy:/src/a.flac',
        'copy:/src/b.mp3',
        'copy:/src/c.mp3',
      ]);
    });

    test('move 走 moveInto 而不是 copyInto', () async {
      final fs = _FakeFileSystem();
      final manager = LocalFileManager(fileSystem: fs);

      await manager.move(['/src/a.flac'], '/dst');

      expect(fs.calls, ['move:/src/a.flac']);
    });

    test('delete 走 deleteFile，成功项没有 targetPath', () async {
      final fs = _FakeFileSystem();
      final manager = LocalFileManager(fileSystem: fs);

      final result = await manager.delete(['/src/a.flac', '/src/b.mp3']);

      expect(result.allSucceeded, isTrue);
      expect(result.results.every((r) => r.targetPath == null), isTrue);
      expect(fs.calls, ['delete:/src/a.flac', 'delete:/src/b.mp3']);
    });

    test('rename 返回新路径，失败时带原始错误', () async {
      final fs = _FakeFileSystem();
      final manager = LocalFileManager(fileSystem: fs);

      final ok = await manager.rename('/src/a.flac', 'new.flac');
      expect(ok.succeeded, isTrue);
      expect(ok.targetPath, '/src/new.flac');

      fs.error = const LocalFileConflictException('/src/new.flac');
      fs.failOn.add('/src/b.mp3');
      final conflict = await manager.rename('/src/b.mp3', 'new.flac');
      expect(conflict.succeeded, isFalse);
      expect(conflict.error, isA<LocalFileConflictException>());
    });

    test('createDirectory 失败不抛，转成失败结果', () async {
      final fs = _FakeFileSystem(failOn: {'/src'});
      final manager = LocalFileManager(fileSystem: fs);

      final result = await manager.createDirectory('/src', 'Music');

      expect(result.succeeded, isFalse);
      expect(result.operation, LocalFileOperation.createDirectory);
    });

    test('平台不支持时 list 返回空列表而不是抛异常', () async {
      final fs = _FakeFileSystem(supported: false);
      final manager = LocalFileManager(fileSystem: fs);

      expect(manager.isSupported, isFalse);
      expect(await manager.list('/anything'), isEmpty);
    });
  });

  group('IoFileSystem 真实文件系统', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('koyze_file_mgr_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    String pathOf(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

    Future<Directory> makeDir(String name) async {
      final dir = Directory(pathOf(name));
      await dir.create();
      return dir;
    }

    test('列目录把文件夹排在文件前面，各自按名字排序', () async {
      await File(pathOf('b.mp3')).writeAsBytes([1, 2, 3]);
      await File(pathOf('a.flac')).writeAsBytes([1]);
      await makeDir('zdir');
      await makeDir('adir');

      final entries = await const IoFileSystem().listDirectory(tempDir.path);

      expect(entries.map((e) => e.name).toList(), [
        'adir',
        'zdir',
        'a.flac',
        'b.mp3',
      ]);
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.size, 3);
      expect(entries.last.isAudio, isTrue);
    });

    test('复制保留文件名，目标已存在时抛冲突而不是静默覆盖', () async {
      final source = File(pathOf('song.mp3'));
      await source.writeAsBytes([7, 7, 7]);
      final target = await makeDir('target');
      const fs = IoFileSystem();

      final copied = await fs.copyInto(source.path, target.path);
      expect(copied, pathOf('target${Platform.pathSeparator}song.mp3'));
      expect(await File(copied).readAsBytes(), [7, 7, 7]);
      // 源还在。
      expect(await source.exists(), isTrue);

      await expectLater(
        fs.copyInto(source.path, target.path),
        throwsA(isA<LocalFileConflictException>()),
      );
    });

    test('移动后源文件消失、目标内容一致', () async {
      final source = File(pathOf('song.mp3'));
      await source.writeAsBytes([9, 8, 7]);
      final target = await makeDir('target');
      const fs = IoFileSystem();

      final moved = await fs.moveInto(source.path, target.path);

      expect(await source.exists(), isFalse);
      expect(await File(moved).readAsBytes(), [9, 8, 7]);
    });

    test('重命名留在同目录，不会把文件挪走', () async {
      final source = File(pathOf('old.mp3'));
      await source.writeAsBytes([1]);
      const fs = IoFileSystem();

      final renamed = await fs.rename(source.path, 'new.mp3');

      expect(renamed, pathOf('new.mp3'));
      expect(await File(renamed).exists(), isTrue);
      expect(await source.exists(), isFalse);
    });

    test('重命名拒绝路径分隔符，防止越权挪动', () async {
      final source = File(pathOf('old.mp3'));
      await source.writeAsBytes([1]);
      const fs = IoFileSystem();

      await expectLater(
        fs.rename(source.path, '../escape.mp3'),
        throwsA(isA<ArgumentError>()),
      );
      // 原文件没被动过。
      expect(await source.exists(), isTrue);
    });

    test('删除不存在的文件是幂等的，不报错', () async {
      const fs = IoFileSystem();
      await fs.deleteFile(pathOf('ghost.mp3'));
    });

    test('createDirectory 建出真实目录', () async {
      const fs = IoFileSystem();
      final created = await fs.createDirectory(tempDir.path, 'Exports');
      expect(Directory(created).existsSync(), isTrue);
    });

    test('exists 对文件、目录都为真，对不存在为假', () async {
      await File(pathOf('a.mp3')).writeAsBytes([1]);
      await makeDir('d');
      const fs = IoFileSystem();

      expect(await fs.exists(pathOf('a.mp3')), isTrue);
      expect(await fs.exists(pathOf('d')), isTrue);
      expect(await fs.exists(pathOf('nope')), isFalse);
    });

    test('listDirectory 对不存在的目录返回空列表', () async {
      const fs = IoFileSystem();
      expect(await fs.listDirectory(pathOf('missing')), isEmpty);
    });
  });

  group('UnsupportedFileSystem', () {
    test('isSupported 为假，所有写操作抛不支持异常', () async {
      const fs = UnsupportedFileSystem();
      expect(fs.isSupported, isFalse);
      await expectLater(
        fs.copyInto('/a.mp3', '/b'),
        throwsA(isA<LocalFileUnsupportedException>()),
      );
      await expectLater(
        fs.moveInto('/a.mp3', '/b'),
        throwsA(isA<LocalFileUnsupportedException>()),
      );
      await expectLater(
        fs.deleteFile('/a.mp3'),
        throwsA(isA<LocalFileUnsupportedException>()),
      );
      expect(await fs.exists('/a.mp3'), isFalse);
    });
  });
}
