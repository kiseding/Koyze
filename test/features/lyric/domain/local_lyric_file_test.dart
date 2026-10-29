import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/lyric/domain/local_lyric_file.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('koyze_sidecar_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  String pathOf(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  test('finds a same-named .lrc next to the audio file', () async {
    final audio = File(pathOf('Song.flac'));
    await audio.writeAsBytes([0]);
    await File(pathOf('Song.lrc')).writeAsString('[00:01.00]hello');

    expect(await readSidecarLyric(audio.path), '[00:01.00]hello');
  });

  test('prefers .lrc over .txt', () async {
    final audio = File(pathOf('Song.mp3'));
    await audio.writeAsBytes([0]);
    await File(pathOf('Song.lrc')).writeAsString('[00:02.00]lonely');
    await File(pathOf('Song.txt')).writeAsString('[00:09.00]other');

    expect(await readSidecarLyric(audio.path), contains('lonely'));
  });

  test('ignores a plain txt that does not look like lyrics', () async {
    final audio = File(pathOf('Track.mp3'));
    await audio.writeAsBytes([0]);
    await File(pathOf('Track.txt')).writeAsString('just one note');

    expect(await readSidecarLyric(audio.path), isNull);
  });

  test('accepts a multi-line txt without time tags', () async {
    final audio = File(pathOf('Track.mp3'));
    await audio.writeAsBytes([0]);
    await File(pathOf('Track.txt')).writeAsString('first line\nsecond line');

    expect(await readSidecarLyric(audio.path), contains('second line'));
  });

  test('returns null when there is no sidecar', () async {
    final audio = File(pathOf('Alone.mp3'));
    await audio.writeAsBytes([0]);

    expect(await readSidecarLyric(audio.path), isNull);
  });

  test('returns null for an extensionless path', () async {
    expect(await readSidecarLyric(pathOf('no_extension')), isNull);
    expect(await readSidecarLyric(''), isNull);
  });

  test('skips an empty file and falls through to the next candidate', () async {
    final audio = File(pathOf('Empty.m4a'));
    await audio.writeAsBytes([0]);
    await File(pathOf('Empty.lrc')).writeAsString('   ');
    await File(pathOf('Empty.LRC')).writeAsString('[00:03.00]real');

    expect(await readSidecarLyric(audio.path), contains('real'));
  });

  test('decodes UTF-8 with a BOM', () {
    final bytes = Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('[00:01.00]你好'),
    ]);

    expect(decodeLyricBytes(bytes), '[00:01.00]你好');
  });

  test('decodes UTF-16 little endian with a BOM', () {
    final text = '[00:01.00]你好';
    final body = <int>[];
    for (final unit in text.codeUnits) {
      body
        ..add(unit & 0xFF)
        ..add((unit >> 8) & 0xFF);
    }

    final decoded = decodeLyricBytes(
      Uint8List.fromList([0xFF, 0xFE, ...body]),
    );

    expect(decoded, text);
  });

  test('decodes UTF-16 big endian with a BOM', () {
    final text = '[00:05.00]hi';
    final body = <int>[];
    for (final unit in text.codeUnits) {
      body
        ..add((unit >> 8) & 0xFF)
        ..add(unit & 0xFF);
    }

    expect(
      decodeLyricBytes(Uint8List.fromList([0xFE, 0xFF, ...body])),
      text,
    );
  });

  test('falls back to latin1 instead of throwing on invalid UTF-8', () {
    // GBK 的 "你" 是 0xC4 0xE3，不是合法的 UTF-8 序列。
    final bytes = Uint8List.fromList([0xC4, 0xE3, 0x0A]);

    expect(() => decodeLyricBytes(bytes), returnsNormally);
    expect(decodeLyricBytes(bytes), hasLength(3));
  });

  test('looksLikeLyric needs a time tag or two non-empty lines', () {
    expect(looksLikeLyric('[00:01.00]x'), isTrue);
    expect(looksLikeLyric('a\nb'), isTrue);
    expect(looksLikeLyric('single'), isFalse);
    expect(looksLikeLyric('\n\n'), isFalse);
  });
}
