import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/custom_source/domain/custom_source_engine.dart';
import 'package:koyze/features/custom_source/domain/source_script_safety.dart';
import 'package:koyze/features/custom_source/domain/source_zlib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'known synchronous loop variants fail closed before evaluation',
    () async {
      final scripts = [
        'while (true) {}',
        'while (1) {}',
        'while (!![]) {}',
        'while (-1) {}',
        'for (;;) {}',
        'for (;;) spin();',
        'do {} while (true)',
        'do {} while (!0)',
        'function a(){return a()} a()',
      ];

      for (final script in scripts) {
        final now = DateTime.now();
        final engine = CustomSourceEngine();
        addTearDown(engine.dispose);
        final source = CustomSource(
          id: 'unsafe',
          name: 'Unsafe',
          description: '',
          version: '1',
          author: 'test',
          script: script,
          createdAt: now,
          updatedAt: now,
        );

        expect(
          await engine
              .loadSource(source)
              .timeout(const Duration(milliseconds: 250)),
          isFalse,
        );
      }
    },
  );

  test('obfuscator string-array rotation is not an unbounded loop', () {
    // 回归用例：曾经因为「看到 `while(!![])` 就当死循环」，fish / flower /
    // sixyin 这批正常音源在 Koyze 里全部「初始化失败，请检查脚本」。
    // 轮转体里有 `break`，不是死循环 —— 别把这里的 isFalse 改回 isTrue。
    const rotation = '''
(function (p, O) {
  const w = p();
  while (!![]) {
    try {
      const r = -parseInt(w[0]) / (-0x15 * 0x121 + 0x3 * 0xf6b);
      if (r === O) break;
      else w['push'](w['shift']());
    } catch (g) {
      w['push'](w['shift']());
    }
  }
}(R, 0x1234));
''';
    expect(hasUnsafeSynchronousLoop(rotation), isFalse);
  });

  test('truthy loops still fail closed when the body has no exit', () {
    expect(hasUnsafeSynchronousLoop('while (!![]) { spin(); }'), isTrue);
    expect(hasUnsafeSynchronousLoop('while (true) { doWork(); }'), isTrue);
    expect(hasUnsafeSynchronousLoop('while (1) spin();'), isTrue);
  });

  test('growth loop is reported separately and does not block', () {
    const growth =
        "for(let i=0,n=items.length;i<n;i++){items.push(1);n=items.length;}"
        "lx.send(lx.EVENT_NAMES.inited,{status:true,sources:{}});";
    expect(hasSynchronousGrowthLoop(growth), isTrue);
    expect(hasUnsafeSynchronousLoop(growth), isFalse);
  });

  test('property calls are not mistaken for self recursion', () {
    expect(
      hasUnsafeSynchronousLoop('''
const md5 = (str) => utils.crypto.md5(str)
function isBuffer(obj) {
  return typeof Buffer !== 'undefined' && Buffer.isBuffer(obj)
}
'''),
      isFalse,
    );
  });

  test('truthy loop text inside comments and strings is ignored', () {    expect(
      hasUnsafeSynchronousLoop('''// while (1) {}
        const text = 'for (;;) {}';
        '''),
      isFalse,
    );
  });

  test('ordinary scripts are not rejected by the safety preflight', () {
    expect(isCustomSourceExecutionSupported, isTrue);
    expect(
      hasUnsafeSynchronousLoop(
        "lx.on(lx.EVENT_NAMES.request, async () => null); "
        "lx.send(lx.EVENT_NAMES.inited, { status: true, sources: {} });",
      ),
      isFalse,
    );
  });

  test('bounded zlib accepts ordinary compressed content', () async {
    final plain = utf8.encode('source payload ' * 100);
    final compressed = ZLibEncoder().convert(plain);

    final encoded = await runBoundedSourceZlib({
      'method': 'inflate',
      'data': base64Encode(compressed),
    });

    expect(base64Decode(encoded), plain);
  });

  test('bounded zlib rejects decoded input over its byte limit', () async {
    final oversized = List<int>.filled(maximumSourceZlibInputBytes + 1, 0);

    await expectLater(
      runBoundedSourceZlib({
        'method': 'inflate',
        'data': base64Encode(oversized),
      }),
      throwsA(isA<SourceZlibLimitException>()),
    );
  });

  test('bounded zlib rejects excessive expansion', () async {
    final bomb = ZLibEncoder().convert(
      List<int>.filled(maximumSourceZlibOutputBytes, 0),
    );

    await expectLater(
      runBoundedSourceZlib({'method': 'inflate', 'data': base64Encode(bomb)}),
      throwsA(isA<SourceZlibLimitException>()),
    );
  });
}
