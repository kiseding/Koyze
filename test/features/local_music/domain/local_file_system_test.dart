import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/local_music/domain/local_file_system.dart';

/// 记录通道调用、按脚本回放结果的假通道。
///
/// 直接用 [MethodChannel] 的真实编解码太绕，这里只关心「发了什么方法、
/// 收到什么错误码之后 Dart 侧怎么反应」，所以拦截 handler 层即可。
class _ChannelHarness {
  _ChannelHarness(this.channel);

  final MethodChannel channel;
  final List<MethodCall> calls = [];
  Object? Function(MethodCall call)? responder;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final respond = responder;
          if (respond == null) return null;
          return respond(call);
        });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChannelFileSystem 错误码翻译', () {
    late _ChannelHarness harness;
    late OhosFileSystem fs;

    setUp(() {
      const channel = MethodChannel('koyze/local_file_system_test');
      harness = _ChannelHarness(channel)..install();
      fs = const OhosFileSystem(channel: channel);
    });

    tearDown(() => harness.remove());

    test('conflict 翻成 LocalFileConflictException', () async {
      harness.responder = (_) => throw PlatformException(code: 'conflict');

      await expectLater(
        fs.copyInto('/src/a.mp3', '/dst'),
        throwsA(isA<LocalFileConflictException>()),
      );
    });

    test('access_denied 翻成 LocalFileAccessDeniedException', () async {
      harness.responder = (_) => throw PlatformException(
        code: 'access_denied',
        message: '目录未授权',
      );

      await expectLater(
        fs.moveInto('/src/a.mp3', '/dst'),
        throwsA(isA<LocalFileAccessDeniedException>()),
      );
    });

    test('未知错误码原样抛 PlatformException，不假装成功', () async {
      harness.responder = (_) => throw PlatformException(code: 'weird');

      await expectLater(
        fs.deleteFile('/src/a.mp3'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('通道没注册时翻成 Unsupported，并带上平台名', () async {
      harness.responder = (_) => throw MissingPluginException();

      await expectLater(
        fs.listDirectory('/src'),
        throwsA(
          isA<LocalFileUnsupportedException>().having(
            (e) => e.platform,
            'platform',
            'HarmonyOS',
          ),
        ),
      );
    });

    test('exists 拿到 null 时当「不存在」，不抛错', () async {
      harness.responder = (_) => null;
      expect(await fs.exists('/nope'), isFalse);
    });
  });

  group('ChannelFileSystem 请求参数', () {
    late _ChannelHarness harness;
    late AndroidSafFileSystem fs;

    setUp(() {
      const channel = MethodChannel('koyze/local_file_system_args');
      harness = _ChannelHarness(channel)..install();
      fs = const AndroidSafFileSystem(channel: channel);
    });

    tearDown(() => harness.remove());

    test('copyInto 发 source/target 两个键', () async {
      harness.responder = (call) => '/dst/a.mp3';

      final target = await fs.copyInto('/src/a.mp3', '/dst');

      expect(target, '/dst/a.mp3');
      final call = harness.calls.single;
      expect(call.method, 'copyInto');
      expect(call.arguments, {'source': '/src/a.mp3', 'target': '/dst'});
    });

    test('rename 把新文件名放在 target 键里，与原生约定一致', () async {
      harness.responder = (call) => '/src/new.mp3';

      await fs.rename('/src/old.mp3', 'new.mp3');

      final call = harness.calls.single;
      expect(call.method, 'rename');
      expect(call.arguments, {'source': '/src/old.mp3', 'target': 'new.mp3'});
    });

    test('createDirectory 用 source=父目录、target=名字', () async {
      harness.responder = (call) => '/src/Music';

      await fs.createDirectory('/src', 'Music');

      expect(harness.calls.single.arguments, {
        'source': '/src',
        'target': 'Music',
      });
    });

    test('列目录结果按「目录优先 + 名字」排序', () async {
      harness.responder = (call) => [
        {
          'name': 'b.mp3',
          'path': '/src/b.mp3',
          'isDirectory': false,
          'size': 2,
          'modifiedAt': 1000,
        },
        {'name': 'zdir', 'path': '/src/zdir', 'isDirectory': true},
        {
          'name': 'A.flac',
          'path': '/src/A.flac',
          'isDirectory': false,
          'size': 1,
        },
      ];

      final entries = await fs.listDirectory('/src');

      expect(entries.map((e) => e.name).toList(), ['zdir', 'A.flac', 'b.mp3']);
      expect(entries.last.modifiedAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(entries.last.isAudio, isTrue);
    });

    test('数字是 double 时也能解析出大小和时间', () async {
      // 鸿蒙侧是 ArkTS 编译到 JS，数字默认 double。严格判 int 会让
      // 每个文件都显示 0 B，所以解析必须接受 num。
      harness.responder = (call) => [
        {
          'name': 'a.mp3',
          'path': '/src/a.mp3',
          'isDirectory': false,
          'size': 2048.0,
          'modifiedAt': 1700000000000.0,
        },
      ];

      final entry = (await fs.listDirectory('/src')).single;

      expect(entry.size, 2048);
      expect(entry.modifiedAt?.millisecondsSinceEpoch, 1700000000000);
    });

    test('重命名带路径分隔符时本地就拦掉，不打到原生', () async {
      await expectLater(
        fs.rename('/src/a.mp3', '../evil.mp3'),
        throwsA(isA<ArgumentError>()),
      );
      expect(harness.calls, isEmpty);
    });
  });

  group('forPlatform 分派', () {
    test('kIsWeb 时返回不支持实现', () {
      // 测试跑在 VM 上，kIsWeb 恒为 false，所以这条只能验证
      // 「非 Web 平台不会误判成 Unsupported」。
      final fs = LocalFileSystem.forPlatform(
        channel: const MethodChannel('koyze/dispatch_test'),
      );
      expect(fs, isNot(isA<UnsupportedFileSystem>()));
    });

    test('ioOverride 优先于平台判断，便于测试注入', () {
      const override = IoFileSystem();
      final fs = LocalFileSystem.forPlatform(ioOverride: override);
      expect(identical(fs, override), isTrue);
    });
  });

  group('AndroidFileSystem 路径分派', () {
    // Android 的下载目录是 getApplicationDocumentsDirectory()/downloads，
    // 属于应用私有目录，dart:io 直接可写；而用户授权的目录是 content://。
    // 混用会让主场景（私有目录 → 公共目录）直接失败，所以这段必须测。

    late _ChannelHarness harness;
    late AndroidFileSystem fs;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('koyze_android_');
      const channel = MethodChannel('koyze/android_dispatch_test');
      harness = _ChannelHarness(channel)..install();
      fs = AndroidFileSystem(channel: channel);
    });

    tearDown(() async {
      harness.remove();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    String pathOf(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

    test('普通路径的列目录走 dart:io，不打原生通道', () async {
      await File(pathOf('a.mp3')).writeAsBytes([1, 2]);

      final entries = await fs.listDirectory(tempDir.path);

      expect(entries.map((e) => e.name), ['a.mp3']);
      expect(harness.calls, isEmpty);
    });

    test('content:// 路径走原生通道', () async {
      harness.responder = (_) => [
        {'name': 'x.mp3', 'path': 'content://koyze/root/x.mp3', 'isDirectory': false},
      ];

      final entries = await fs.listDirectory('content://koyze/root');

      expect(entries.single.name, 'x.mp3');
      expect(harness.calls.single.method, 'listDirectory');
    });

    test('两边都是普通路径时复制走 dart:io', () async {
      final source = File(pathOf('a.mp3'));
      await source.writeAsBytes([5]);
      final target = Directory(pathOf('dst'));
      await target.create();

      final copied = await fs.copyInto(source.path, target.path);

      expect(await File(copied).readAsBytes(), [5]);
      expect(harness.calls, isEmpty);
    });

    test('私有目录 → content:// 交给原生做跨源搬运', () async {
      harness.responder = (call) {
        expect(call.method, 'moveAcross');
        return 'content://koyze/root/a.mp3';
      };

      final moved = await fs.moveInto(
        pathOf('a.mp3'),
        'content://koyze/root',
      );

      expect(moved, 'content://koyze/root/a.mp3');
      expect(harness.calls.single.arguments, {
        'source': pathOf('a.mp3'),
        'target': 'content://koyze/root',
      });
    });

    test('跨源冲突翻成 LocalFileConflictException', () async {
      harness.responder = (_) => throw PlatformException(code: 'conflict');

      await expectLater(
        fs.copyInto(pathOf('a.mp3'), 'content://koyze/root'),
        throwsA(isA<LocalFileConflictException>()),
      );
    });

    test('跨源无权限翻成 LocalFileAccessDeniedException', () async {
      harness.responder = (_) =>
          throw PlatformException(code: 'access_denied');

      await expectLater(
        fs.copyInto(pathOf('a.mp3'), 'content://koyze/root'),
        throwsA(isA<LocalFileAccessDeniedException>()),
      );
    });

    test('普通路径的 rename 留在 dart:io，不碰原生', () async {
      final source = File(pathOf('old.mp3'));
      await source.writeAsBytes([1]);

      final renamed = await fs.rename(source.path, 'new.mp3');

      expect(renamed, pathOf('new.mp3'));
      expect(harness.calls, isEmpty);
    });

    test('普通路径的 delete 也是 dart:io', () async {
      final source = File(pathOf('a.mp3'));
      await source.writeAsBytes([1]);

      await fs.deleteFile(source.path);

      expect(await source.exists(), isFalse);
      expect(harness.calls, isEmpty);
    });
  });

  group('目录选择器分派', () {
    // 桌面 / Android / iOS 用 file_picker；鸿蒙必须用原生选择器，
    // 因为它的 file_picker 移植把「选目录」实现成了「选文件读进缓存」。
    const channel = MethodChannel('koyze/pick_directory_test');

    test('鸿蒙需要原生选择器，并把空串翻成 null', () async {
      final harness = _ChannelHarness(channel)..install();
      addTearDown(harness.remove);
      final fs = const OhosFileSystem(channel: channel);

      expect(fs.needsNativeDirectoryPicker, isTrue);

      harness.responder = (_) => '/storage/Users/currentUser/Download';
      expect(await fs.pickDirectory(), '/storage/Users/currentUser/Download');

      // 原生侧用空串表示用户取消。
      harness.responder = (_) => '';
      expect(await fs.pickDirectory(), isNull);
    });

    test('桌面与 Android 不用原生选择器', () {
      expect(const IoFileSystem().needsNativeDirectoryPicker, isFalse);
      expect(
        AndroidFileSystem(channel: channel).needsNativeDirectoryPicker,
        isFalse,
      );
      expect(
        const AndroidSafFileSystem(channel: channel).needsNativeDirectoryPicker,
        isFalse,
      );
      expect(const AppleFileSystem(channel: channel).needsNativeDirectoryPicker,
          isFalse);
      expect(
        const UnsupportedFileSystem().needsNativeDirectoryPicker,
        isFalse,
      );
    });

    test('默认 pickDirectory 返回 null，UI 会退回 file_picker', () async {
      expect(await const IoFileSystem().pickDirectory(), isNull);
    });
  });
}
