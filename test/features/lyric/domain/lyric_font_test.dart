import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/lyric/domain/lyric_font.dart';

/// 造一段「看起来像 TrueType」的字节：只满足文件头，内容不合法也没关系——
/// 校验函数只读 magic number，真正的解析交给引擎。
Uint8List fakeSfnt({int length = 4096, int magic = 0x00010000}) {
  final bytes = Uint8List(length);
  ByteData.sublistView(bytes).setUint32(0, magic);
  return bytes;
}

void main() {
  group('扩展名', () {
    test('ttf / otf 认为可用，大小写无关', () {
      expect(isSupportedLyricFontName('思源黑体.ttf'), isTrue);
      expect(isSupportedLyricFontName('SourceHanSans.OTF'), isTrue);
    });

    test('网页字体和字体集合不接受', () {
      // woff/woff2 是压缩封装，引擎读不了；ttc 是集合，FontLoader 不支持索引。
      expect(isSupportedLyricFontName('font.woff'), isFalse);
      expect(isSupportedLyricFontName('font.woff2'), isFalse);
      expect(isSupportedLyricFontName('font.ttc'), isFalse);
    });

    test('没有扩展名或扩展名在末尾时视为不支持', () {
      expect(isSupportedLyricFontName('font'), isFalse);
      expect(isSupportedLyricFontName('font.'), isFalse);
    });

    test('只取最后一段扩展名', () {
      expect(lyricFontExtensionOf('a.b.ttf'), 'ttf');
      expect(lyricFontExtensionOf('目录.名字/字体.otf'), 'otf');
    });
  });

  group('文件头', () {
    test('TrueType 与 CFF 都认', () {
      expect(looksLikeFontBytes(fakeSfnt(magic: 0x00010000)), isTrue);
      expect(looksLikeFontBytes(fakeSfnt(magic: 0x74727565)), isTrue); // 'true'
      expect(looksLikeFontBytes(fakeSfnt(magic: 0x4F54544F)), isTrue); // 'OTTO'
    });

    test('集合（ttcf）不算单体字体', () {
      expect(looksLikeFontBytes(fakeSfnt(magic: 0x74746366)), isFalse);
    });

    test('把图片改名成 ttf 会被拦下', () {
      final png = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        ...List<int>.filled(64, 0),
      ]);
      expect(looksLikeFontBytes(png), isFalse);
    });

    test('太短的文件直接判否，不做越界读', () {
      expect(looksLikeFontBytes(Uint8List(4)), isFalse);
    });
  });

  group('校验', () {
    test('正常字体通过', () {
      expect(
        () => validateLyricFont(fileName: 'a.ttf', bytes: fakeSfnt()),
        returnsNormally,
      );
    });

    test('格式不支持', () {
      expect(
        () => validateLyricFont(fileName: 'a.woff2', bytes: fakeSfnt()),
        throwsA(
          isA<LyricFontException>().having(
            (e) => e.issue,
            'issue',
            LyricFontIssue.unsupportedFormat,
          ),
        ),
      );
    });

    test('空文件', () {
      expect(
        () => validateLyricFont(fileName: 'a.ttf', bytes: Uint8List(0)),
        throwsA(
          isA<LyricFontException>().having(
            (e) => e.issue,
            'issue',
            LyricFontIssue.emptyFile,
          ),
        ),
      );
    });

    test('超过上限', () {
      expect(
        () => validateLyricFont(
          fileName: 'a.ttf',
          bytes: fakeSfnt(length: kLyricFontMaxBytes + 1),
        ),
        throwsA(
          isA<LyricFontException>().having(
            (e) => e.issue,
            'issue',
            LyricFontIssue.tooLarge,
          ),
        ),
      );
    });

    test('扩展名对但内容不是字体', () {
      final bytes = Uint8List.fromList(List<int>.filled(4096, 0x41)); // 'AAAA'
      expect(
        () => validateLyricFont(fileName: 'a.ttf', bytes: bytes),
        throwsA(
          isA<LyricFontException>().having(
            (e) => e.issue,
            'issue',
            LyricFontIssue.invalidData,
          ),
        ),
      );
    });
  });

  group('字体族名', () {
    test('同一份内容总是同一个族名', () {
      final a = lyricFontFamilyFor(fakeSfnt());
      final b = lyricFontFamilyFor(fakeSfnt());
      expect(a, b);
      expect(a, startsWith('KoyzeLyric-'));
    });

    test('不同内容得到不同族名，换字体不会复用上次的注册', () {
      final a = lyricFontFamilyFor(fakeSfnt(magic: 0x00010000));
      final b = lyricFontFamilyFor(fakeSfnt(magic: 0x4F54544F));
      expect(a, isNot(b));
    });
  });
}
