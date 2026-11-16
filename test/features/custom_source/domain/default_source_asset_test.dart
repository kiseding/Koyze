import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/custom_source/domain/custom_source_engine.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/custom_source/domain/source_script_safety.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('初始安装不自动添加自定义源', () async {
    SharedPreferences.setMockInitialValues({});
    final service = CustomSourceService();
    await service.init();
    expect(service.sources, isEmpty);
    service.dispose();
  });

  test(
    'initialization retains persisted ordinary custom sources enabled',
    () async {
      final now = DateTime.now().toIso8601String();
      SharedPreferences.setMockInitialValues({
        'custom_sources':
            '''
[{"id":"legacy-source","name":"Saved Source","description":"","version":"1.0.0","author":"Author","script":"EVENT_NAMES","createdAt":"$now","updatedAt":"$now","isEnabled":true}]
''',
      });
      final service = CustomSourceService(
        storage: StorageService.forTesting(
          await SharedPreferences.getInstance(),
        ),
      );
      await service.init();
      expect(service.sources.single.id, 'legacy-source');
      expect(service.sources.single.isEnabled, isTrue);
      service.dispose();
    },
  );

  test(
    'initialization salvages valid siblings and quarantines bad records',
    () async {
      final now = DateTime.utc(2026).toIso8601String();
      SharedPreferences.setMockInitialValues({
        'custom_sources': jsonEncode([
          {
            'id': 'valid',
            'name': 'Valid',
            'description': '',
            'version': '1',
            'author': 'A',
            'script': 'search',
            'createdAt': now,
            'updatedAt': now,
            'isEnabled': true,
          },
          {'id': 7},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = CustomSourceService(
        storage: StorageService.forTesting(prefs),
        clock: () => DateTime.utc(2026),
      );

      await service.init();

      expect(service.sources.map((source) => source.id), ['valid']);
      expect(jsonDecode(prefs.getString('custom_sources')!), hasLength(1));
      expect(
        jsonDecode(prefs.getString('custom_sources_quarantine')!),
        hasLength(1),
      );
      service.dispose();
    },
  );

  test(
    'corrupted root cannot fail initialization even if recovery write fails',
    () async {
      SharedPreferences.setMockInitialValues({'custom_sources': '{broken'});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService.forTesting(
        prefs,
        writeOverride: (_, __, ___) async => false,
      );
      final service = CustomSourceService(storage: storage);

      await service.init();

      expect(service.sources, isEmpty);
      service.dispose();
    },
  );

  test(
    'obfuscator growth loop is a diagnostic, not an init blocker',
    () async {
      final now = DateTime.now().toIso8601String();
      const dangerous =
          "new RegExp('x'); function f(){return 'x'}; f['toString'](); "
          "for(let i=0,n=this['items']['length'];i<n;i++){"
          "this['items']['push'](1);n=this['items']['length'];}";
      SharedPreferences.setMockInitialValues({
        'custom_sources': jsonEncode([
          {
            'id': 'unsafe',
            'name': 'Unsafe',
            'description': '',
            'version': '1',
            'author': 'A',
            'script': dangerous,
            'createdAt': now,
            'updatedAt': now,
            'isEnabled': true,
          },
        ]),
      });
      final service = CustomSourceService(
        storage: StorageService.forTesting(
          await SharedPreferences.getInstance(),
        ),
      );

      await service.init();

      // 混淆器的 debug-protection 陷阱就是这个形状：正常加载走不到，
      // 不能因为它的存在把整份音源拒掉（fish 里就带着一段）。
      // 下面两个 isFalse / isTrue 是刻意的，改回去就会重现「音源全部
      // 初始化失败，请检查脚本」那次故障。
      expect(hasSynchronousGrowthLoop(dangerous), isTrue);
      expect(hasUnsafeSynchronousLoop(dangerous), isFalse);
      expect(service.sources.single.isEnabled, isTrue);
      service.dispose();
    },
  );

  test('growth loop is reported but does not block enabling', () async {
    SharedPreferences.setMockInitialValues({});
    final service = CustomSourceService(
      storage: StorageService.forTesting(await SharedPreferences.getInstance()),
    );
    await service.init();
    final now = DateTime.now();
    const dangerous =
        "new RegExp('x'); function f(){return 'x'}; f['toString'](); "
        "for(let i=0,n=this['items']['length'];i<n;i++){"
        "this['items']['push'](1);n=this['items']['length'];}";
    await service.addSource(
      CustomSource(
        id: 'unsafe',
        name: 'Unsafe',
        description: '',
        version: '1',
        author: 'A',
        script: dangerous,
        createdAt: now,
        updatedAt: now,
        isEnabled: false,
      ),
    );

    // 报告归报告，不再拿它当拒绝启用的依据——否则 fish / sixyin 这类
    // 带 debug-protection 的正常音源全都用不了。
    expect(CustomSourceService.hasUnsafeSynchronousLoop(dangerous), isFalse);
    expect(hasSynchronousGrowthLoop(dangerous), isTrue);
    service.dispose();
  });

  test('bounded loops and ordinary minified scripts remain allowed', () {
    const bounded =
        "for(let i=0,n=items.length;i<n;i++){items.push(i)};lx.send('inited',{});";
    expect(CustomSourceService.hasUnsafeSynchronousLoop(bounded), isFalse);
  });

  test('obvious synchronous loops and unguarded recursion are rejected', () {
    expect(
      CustomSourceService.hasUnsafeSynchronousLoop('while (true) {}'),
      isTrue,
    );
    expect(CustomSourceService.hasUnsafeSynchronousLoop('for (;;) {}'), isTrue);
    expect(
      CustomSourceService.hasUnsafeSynchronousLoop('do {} while (true)'),
      isTrue,
    );
    expect(
      CustomSourceService.hasUnsafeSynchronousLoop('function f(){f();}'),
      isTrue,
    );
    expect(
      CustomSourceService.hasUnsafeSynchronousLoop('const f = () => f();'),
      isTrue,
    );
    expect(
      CustomSourceService.hasUnsafeSynchronousLoop(
        'function f(n){if(n>0)return f(n-1);return 0;}',
      ),
      isFalse,
    );
    expect(
      CustomSourceService.hasUnsafeSynchronousLoop(
        'const text = "while (true) {}"; // for (;;) {}',
      ),
      isFalse,
    );
  });

  test(
    'engine rejects unsafe script before creating a JavaScript runtime',
    () async {
      final now = DateTime.now();
      // 样本必须是**没有出口**的恒真循环。增长型循环已经降级成诊断
      // （见 source_script_safety.dart），宿主带 JS 运行时时它会被真的执行，
      // 拿它当「预检拦截」的样本会在 macOS CI 上失败——Windows / Linux 主机
      // 没有 QuickJS/JSC，任何脚本 loadSource 都返回 false，骗得过本地。
      const dangerous = 'while (true) { spin(); }';
      final engine = CustomSourceEngine();
      final source = CustomSource(
        id: 'unsafe',
        name: 'Unsafe',
        description: '',
        version: '1',
        author: 'A',
        script: dangerous,
        createdAt: now,
        updatedAt: now,
      );

      // 断言预检本身拦截，这样在没有 JS 运行时的宿主上用例也不是空转。
      expect(hasUnsafeSynchronousLoop(dangerous), isTrue);
      expect(await engine.loadSource(source), isFalse);
      engine.dispose();
    },
  );

  test('enabled JSON import stays enabled for growth-loop scripts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = CustomSourceService(
      storage: StorageService.forTesting(prefs),
    );
    await service.init();
    final now = DateTime.now();
    const dangerous =
        "new RegExp('x'); function f(){return 'x'}; f['toString'](); "
        "for(let i=0,n=this['items']['length'];i<n;i++){"
        "this['items']['push'](1);n=this['items']['length'];}";
    final source = CustomSource(
      id: 'unsafe-import',
      name: 'Unsafe Import',
      description: '',
      version: '1',
      author: 'A',
      script: dangerous,
      createdAt: now,
      updatedAt: now,
      isEnabled: true,
    );

    expect(await service.importSource(jsonEncode(source.toJson())), isTrue);

    // 增长型循环只出诊断、不触发自动降级，所以启用状态原样保留。
    expect(service.sources.single.isEnabled, isTrue);
    final persisted = jsonDecode(prefs.getString('custom_sources')!) as List;
    expect((persisted.single as Map<String, dynamic>)['isEnabled'], isTrue);
    service.dispose();
  });

  test('failed durable import does not report or retain success', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService.forTesting(
      prefs,
      writeOverride: (operation, key, value) async => key != 'custom_sources',
    );
    final service = CustomSourceService(storage: storage);
    await service.init();

    expect(
      await service.importLxMusicScript('/* @name Test */\nsearch'),
      isFalse,
    );

    expect(service.sources, isEmpty);
    service.dispose();
  });

  test('failed durable delete keeps the in-memory source', () async {
    final now = DateTime.now().toIso8601String();
    SharedPreferences.setMockInitialValues({
      'custom_sources':
          '''
[{"id":"user-source","name":"User","description":"","version":"1.0.0","author":"Me","script":"search","createdAt":"$now","updatedAt":"$now","isEnabled":true}]
''',
    });
    final prefs = await SharedPreferences.getInstance();
    var failWrites = false;
    final storage = StorageService.forTesting(
      prefs,
      writeOverride: (operation, key, value) async => !failWrites,
    );
    final service = CustomSourceService(storage: storage);
    await service.init();
    failWrites = true;

    await expectLater(
      service.deleteSource('user-source'),
      throwsA(isA<StorageWriteException>()),
    );

    expect(service.sources.single.id, 'user-source');
    service.dispose();
  });

  test(
    'delayed failed mutation cannot overwrite a later successful mutation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final firstWrite = Completer<bool>();
      final writes = <String>[];
      final storage = StorageService.forTesting(
        prefs,
        writeOverride: (operation, key, value) async {
          if (key != 'custom_sources') return true;
          final raw = value! as String;
          writes.add(raw);
          if (writes.length == 1) return firstWrite.future;
          await prefs.setString(key, raw);
          return true;
        },
      );
      final service = CustomSourceService(storage: storage);
      await service.init();

      final failed = service.importLxMusicScript('/* @name A */\nsearch');
      final succeeded = service.importLxMusicScript('/* @name B */\nsearch');
      await Future<void>.delayed(Duration.zero);
      expect(writes, hasLength(1));

      firstWrite.complete(false);
      expect(await failed, isFalse);
      expect(await succeeded, isTrue);

      final durable = (jsonDecode(prefs.getString('custom_sources')!) as List)
          .cast<Map<String, dynamic>>();
      expect(service.sources.map((source) => source.name), ['B']);
      expect(durable.map((source) => source['name']), ['B']);
      expect(writes, hasLength(2));
      service.dispose();
    },
  );

  test('deduplicating add performs one durable source write', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var sourceWrites = 0;
    final storage = StorageService.forTesting(
      prefs,
      writeOverride: (operation, key, value) async {
        if (key == 'custom_sources') sourceWrites++;
        return true;
      },
    );
    final service = CustomSourceService(storage: storage);
    await service.init();
    final now = DateTime.now();
    final source = CustomSource(
      id: 'same',
      name: 'Same',
      description: '',
      version: '1',
      author: 'Author',
      script: 'search',
      createdAt: now,
      updatedAt: now,
    );

    await service.addSource(source);
    sourceWrites = 0;
    await service.addSource(
      source.copyWith(updatedAt: now.add(const Duration(seconds: 1))),
    );

    expect(sourceWrites, 1);
    service.dispose();
  });

  test(
    'every public source mutation performs at most one durable save',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var sourceWrites = 0;
      final storage = StorageService.forTesting(
        prefs,
        writeOverride: (operation, key, value) async {
          if (key == 'custom_sources') sourceWrites++;
          return true;
        },
      );
      final service = CustomSourceService(storage: storage);
      await service.init();
      final now = DateTime.now();
      final source = CustomSource(
        id: 'one',
        name: 'One',
        description: '',
        version: '1',
        author: 'Author',
        script: 'search',
        createdAt: now,
        updatedAt: now,
      );

      Future<void> expectOneSave(Future<void> Function() mutation) async {
        final before = sourceWrites;
        await mutation();
        expect(sourceWrites - before, 1);
      }

      await expectOneSave(() => service.addSource(source));
      await expectOneSave(
        () => service.updateSource(source.copyWith(version: '2')),
      );
      await expectOneSave(() async {
        expect(await service.toggleSource(source.id), isTrue);
      });
      await expectOneSave(() async {
        expect(
          await service.importSource(
            jsonEncode(source.copyWith(id: 'two').toJson()),
          ),
          isTrue,
        );
      });
      await expectOneSave(() async {
        expect(
          await service.importLxMusicScript('/* @name Script */\nsearch'),
          isTrue,
        );
      });
      await expectOneSave(() => service.deleteSource(source.id));

      service.dispose();
    },
  );
}
