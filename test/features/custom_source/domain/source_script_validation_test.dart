import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/custom_source/domain/source_script_validation.dart';

void main() {
  test('parses metadata from the leading block header', () {
    final header = parseSourceScriptHeader('''
/*!
 * @name Pasted source
 * @version 1.2
 */
globalThis.someObfuscatedName = 1;
''');

    expect(header?['name'], 'Pasted source');
    expect(header?['version'], '1.2');
    expect(isValidSourceScript('const x = 1;'), isFalse);
  });

  // Windows 编辑器与 GitHub 网页上传普遍写 CRLF。回归用例：Dart 的 `.` 不匹配
  // `\r`、`$` 又只锚串尾，曾导致 `@name xxx\r` 整行失配，头部解析出空 name，
  // 远程导入被误判为「脚本头部无效」。
  test('parses metadata from a CRLF header', () {
    const script =
        '/*!\r\n'
        ' * @name 巡回寺 QQ + 网易云 + 酷我 + 酷狗\r\n'
        ' * @description 多平台解析\r\n'
        ' * @version 1.3.0\r\n'
        ' * @author kiseding\r\n'
        ' */\r\n'
        'var a = 1;\r\n';

    final header = parseSourceScriptHeader(script);
    expect(header, isNotNull);
    expect(header!['name'], '巡回寺 QQ + 网易云 + 酷我 + 酷狗');
    expect(header['description'], '多平台解析');
    expect(header['version'], '1.3.0');
    expect(header['author'], 'kiseding');
    expect(isValidSourceScript(script), isTrue);
  });

  test('parses metadata from a bare CR header', () {
    const script = '/*!\r * @name CR source\r * @author me\r */\r';

    final header = parseSourceScriptHeader(script);
    expect(header?['name'], 'CR source');
    expect(header?['author'], 'me');
  });

  test('CRLF and LF headers yield identical metadata', () {
    const body = ' * @name Same\n * @author dev\n * @version 2.0.0\n';
    final lf = parseSourceScriptHeader('/*!\n$body*/');
    final crlf = parseSourceScriptHeader(
      '/*!\n${body.replaceAll('\n', '\r\n')}*/',
    );

    expect(crlf?['name'], lf?['name']);
    expect(crlf?['author'], lf?['author']);
    expect(crlf?['version'], lf?['version']);
  });

  test('ignores empty metadata values', () {
    final header = parseSourceScriptHeader(
      '/*!\n * @name\n * @author dev\n */',
    );
    expect(header?['name'], isNull);
    expect(header?['author'], 'dev');
    expect(isValidSourceScript('/*!\n * @name\n */'), isFalse);
  });

  test('closing marker on the last metadata line is stripped', () {
    final header = parseSourceScriptHeader('/*!\n * @name Last line */');
    expect(header?['name'], 'Last line');
  });
}
