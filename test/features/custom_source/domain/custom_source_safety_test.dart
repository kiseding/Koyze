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
        'for (;;) {}',
        'do {} while (true)',
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
