import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/download/domain/download_service.dart';
import 'package:koyze/features/download/domain/download_task.dart';

/// 下载目录的三件事：切换后立刻生效、旧目录里的文件仍然归本服务、写不进去
/// 的位置必须被拒。
///
/// 第三条是这组测试的重点。Android 的 SAF 目录是 `content://` 树，dart:io
/// 打不开；只读的卷、指向文件的路径也一样。把这些值存进设置的话，失败会推迟
/// 到「下一首歌下载」时才暴露，而那时用户已经不知道是自己选错了目录。
class _MemoryStorage implements DownloadTaskStorage {
  _MemoryStorage({this.saved = const [], this.roots = const []});

  List<Map<String, dynamic>> saved;
  List<String> roots;
  List<Map<String, dynamic>> quarantine = [];

  @override
  List<dynamic> load() => saved;

  @override
  Future<void> save(List<Map<String, dynamic>> tasks) async {
    saved = tasks;
  }

  @override
  List<Map<String, dynamic>> loadQuarantine() => quarantine;

  @override
  Future<void> saveQuarantine(List<Map<String, dynamic>> records) async {
    quarantine = records;
  }

  @override
  List<String> loadRoots() => roots;

  @override
  Future<void> saveRoots(List<String> value) async {
    roots = value;
  }
}

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('koyze_download_dir_');
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Directory sub(String name) => Directory('${sandbox.path}/$name');

  DownloadService buildService({
    required Directory fallback,
    _MemoryStorage? storage,
    String? customDirectory,
  }) {
    return DownloadService(
      storage: storage ?? _MemoryStorage(),
      downloader: (_, _, _) async {},
      downloadDirectory: () async => fallback,
      customDownloadDirectory: customDirectory,
    );
  }

  test('选择一个新目录后立刻生效，目录会被创建', () async {
    final fallback = sub('fallback')..createSync(recursive: true);
    final service = buildService(fallback: fallback);
    addTearDown(service.dispose);
    await service.init();
    expect(service.downloadDirectory, fallback.path);
    expect(service.customDownloadDirectory, isNull);

    final target = '${sandbox.path}/picked';
    final applied = await service.switchDownloadDirectory(target);

    expect(applied, target);
    expect(service.downloadDirectory, target);
    expect(service.customDownloadDirectory, target);
    expect(Directory(target).existsSync(), isTrue);
    expect(service.isOwnedDownloadPath('$target/song.mp3'), isTrue);
  });

  test('启动时直接采用持久化的自定义目录', () async {
    final fallback = sub('fallback')..createSync(recursive: true);
    final target = '${sandbox.path}/persisted';
    final service = buildService(fallback: fallback, customDirectory: target);
    addTearDown(service.dispose);

    await service.init();

    expect(service.downloadDirectory, target);
    expect(service.customDownloadDirectory, target);
    expect(Directory(target).existsSync(), isTrue);
  });

  test('旧目录不会因为换目录而失去归属，且会写进持久化', () async {
    final fallback = sub('fallback')..createSync(recursive: true);
    final storage = _MemoryStorage();
    final service = buildService(fallback: fallback, storage: storage);
    addTearDown(service.dispose);
    await service.init();
    final oldFile = File('${fallback.path}/old.mp3')
      ..writeAsBytesSync([1, 2, 3]);

    await service.switchDownloadDirectory('${sandbox.path}/picked');

    expect(
      service.isOwnedDownloadPath(oldFile.path),
      isTrue,
      reason: '换目录后旧文件仍要能被删除、统计，否则它们就成了孤儿',
    );
    expect(
      storage.roots,
      contains(await fallback.resolveSymbolicLinks()),
      reason: '归属历史必须落盘，否则重启后旧下载会被当成越权路径隔离',
    );
  });

  test('换过目录后重启，旧目录里的已完成任务不会被隔离', () async {
    final fallback = sub('fallback')..createSync(recursive: true);
    final current = sub('current')..createSync(recursive: true);
    final file = File('${fallback.path}/song-abcd1234-1.mp3')
      ..writeAsBytesSync([1, 2, 3]);
    final storage = _MemoryStorage(
      roots: [await fallback.resolveSymbolicLinks()],
      saved: [
        DownloadTask(
          id: 'abcd1234',
          musicId: 'm1',
          name: 'Song',
          singer: 'Singer',
          createdAt: DateTime.utc(2026),
          status: DownloadStatus.completed,
          progress: 1,
          savePath: file.path,
          fileSize: 3,
        ).toJson(),
      ],
    );
    final service = buildService(
      fallback: current,
      storage: storage,
      customDirectory: null,
    );
    addTearDown(service.dispose);

    await service.init();

    expect(storage.quarantine, isEmpty);
    expect(service.tasks.map((task) => task.id), ['abcd1234']);
    expect(service.isOwnedDownloadPath(file.path), isTrue);
  });

  test('content:// 目录被拒绝，当前目录保持不变', () async {
    final fallback = sub('fallback')..createSync(recursive: true);
    final service = buildService(fallback: fallback);
    addTearDown(service.dispose);
    await service.init();

    await expectLater(
      service.switchDownloadDirectory(
        'content://com.android.externalstorage.documents/tree/primary%3ADownload',
      ),
      throwsA(
        isA<DownloadDirectoryException>().having(
          (error) => error.reason,
          'reason',
          'unsupported_scheme',
        ),
      ),
    );
    expect(service.downloadDirectory, fallback.path);
    expect(service.customDownloadDirectory, isNull);
  });

  test('写不进去的目录被拒绝，当前目录保持不变', () async {
    final fallback = sub('fallback')..createSync(recursive: true);
    final service = buildService(fallback: fallback);
    addTearDown(service.dispose);
    await service.init();
    final blocker = File('${sandbox.path}/blocker')..writeAsStringSync('x');

    await expectLater(
      service.switchDownloadDirectory(
        '${blocker.path}${Platform.pathSeparator}nested',
      ),
      throwsA(
        isA<DownloadDirectoryException>().having(
          (error) => error.reason,
          'reason',
          'not_writable',
        ),
      ),
    );
    expect(service.downloadDirectory, fallback.path);
  });

  test('恢复默认会清掉自定义目录，回到构造时的默认位置', () async {
    final fallback = sub('fallback')..createSync(recursive: true);
    final service = buildService(fallback: fallback);
    addTearDown(service.dispose);
    await service.init();
    await service.switchDownloadDirectory('${sandbox.path}/picked');

    final applied = await service.switchDownloadDirectory(null);

    expect(applied, fallback.path);
    expect(service.downloadDirectory, fallback.path);
    expect(service.customDownloadDirectory, isNull);
  });
}
