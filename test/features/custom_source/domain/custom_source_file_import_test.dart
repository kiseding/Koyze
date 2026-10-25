import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/io/bounded_input.dart';
import 'package:koyze/core/logging/app_log.dart';
import 'package:koyze/features/custom_source/domain/custom_source_file_import.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads a selected file from its local path', () async {
    final directory = await Directory.systemTemp.createTemp('koyze-source-');
    addTearDown(() => directory.delete(recursive: true));
    final fileOnDisk = File(
      '${directory.path}${Platform.pathSeparator}source.js',
    );
    final expected = Uint8List.fromList(utf8.encode('/* @name Path source */'));
    await fileOnDisk.writeAsBytes(expected);

    final file = PlatformFile(
      name: 'source.js',
      size: expected.length,
      path: fileOnDisk.path,
    );

    final result = await readCustomSourceFileBytes(file, maximumBytes: 1024);

    expect(result.source, 'path');
    expect(result.bytes, expected);
  });

  test('reads bytes when the picker has no local path', () async {
    final expected = Uint8List.fromList(
      utf8.encode('/* @name Bytes source */'),
    );
    final file = PlatformFile(
      name: 'source.js',
      size: expected.length,
      bytes: expected,
    );

    final result = await readCustomSourceFileBytes(file, maximumBytes: 1024);

    expect(result.source, 'bytes');
    expect(result.bytes, expected);
  });

  test('reads a stream when path and bytes are unavailable', () async {
    final expected = Uint8List.fromList(
      utf8.encode('/* @name Stream source */'),
    );
    final file = PlatformFile(
      name: 'source.js',
      size: expected.length,
      readStream: Stream<List<int>>.fromIterable([
        expected.sublist(0, 8).toList(),
        expected.sublist(8).toList(),
      ]),
    );

    final result = await readCustomSourceFileBytes(file, maximumBytes: 1024);

    expect(result.source, 'readStream');
    expect(result.bytes, expected);
  });

  test('reports when the picker provides no readable content', () async {
    final file = PlatformFile(name: 'source.js', size: 0);

    expect(
      () => readCustomSourceFileBytes(file, maximumBytes: 1024),
      throwsA(
        isA<CustomSourceFileReadException>().having(
          (error) => error.message,
          'message',
          contains('没有返回可读取'),
        ),
      ),
    );
  });

  test('enforces the byte limit for picker bytes and streams', () async {
    final oversized = Uint8List.fromList(List<int>.filled(5, 65));
    final bytesFile = PlatformFile(
      name: 'source.js',
      size: oversized.length,
      bytes: oversized,
    );
    final streamFile = PlatformFile(
      name: 'source.js',
      size: oversized.length,
      readStream: Stream.value(oversized),
    );

    expect(
      () => readCustomSourceFileBytes(bytesFile, maximumBytes: 4),
      throwsA(isA<InputLimitException>()),
    );
    expect(
      () => readCustomSourceFileBytes(streamFile, maximumBytes: 4),
      throwsA(isA<InputLimitException>()),
    );
  });

  test('strips a UTF-8 BOM before decoding the script', () {
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('/* @name BOM */')];

    expect(
      decodeCustomSourceScript(Uint8List.fromList(bytes)),
      '/* @name BOM */',
    );
  });

  test('returns an import reason and records failed validation', () async {
    AppLog.instance.clear();
    final service = CustomSourceService();
    addTearDown(() {
      service.dispose();
      AppLog.instance.clear();
    });

    final result = await service.importLxMusicScriptWithResult(
      'const source = 1;',
    );

    expect(result.success, isFalse);
    expect(result.reason, contains('非空的 @name'));
    expect(
      AppLog.instance.entries.value,
      anyElement(
        isA<AppLogEntry>()
            .having(
              (entry) => entry.category,
              'category',
              'custom_source.import',
            )
            .having((entry) => entry.message, 'message', contains('@name')),
      ),
    );
  });
}
