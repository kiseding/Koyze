import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/custom_source/domain/custom_source_export.dart';

void main() {
  CustomSource source({String name = '测试音源'}) {
    return CustomSource(
      id: 'src-1',
      name: name,
      description: '一个用于测试的音源',
      version: '2.0.0',
      author: 'Tester',
      homepage: 'https://example.com',
      script: '/* @name 测试音源 */\n(function(){return 1})();',
      createdAt: DateTime.utc(2026, 11, 24),
      updatedAt: DateTime.utc(2026, 11, 24, 12),
      isEnabled: false,
    );
  }

  test('导出的文件能被原样再导入', () {
    final export = buildSourceExport(source());
    final restored = CustomSource.fromJson(
      jsonDecode(export.contents) as Map<String, dynamic>,
    );

    expect(restored.id, 'src-1');
    expect(restored.name, '测试音源');
    expect(restored.script, source().script);
    expect(restored.author, 'Tester');
    // 导出前是关掉的音源，导入后不能自己变成启用状态。
    expect(restored.isEnabled, isFalse);
  });

  test('文件名替换掉路径与通配非法字符', () {
    expect(safeSourceFileName('A/B: 音源'), 'A_B_ 音源');
    expect(safeSourceFileName(r'音源\v2*?'), '音源_v2__');
    expect(
      buildSourceExport(source(name: 'A/B: 音源')).fileName,
      'koyze_source_A_B_ 音源.json',
    );
  });

  test('名字不可用时回退到默认文件名', () {
    expect(safeSourceFileName(''), 'custom_source');
    expect(safeSourceFileName('   '), 'custom_source');
  });

  test('字节内容是 UTF-8 编码的 JSON', () {
    final export = buildSourceExport(source());
    expect(utf8.decode(export.bytes), export.contents);
    // 手机上没有可读的文本预览，缩进只是为了桌面端看起来正常。
    expect(export.contents, contains('\n  "id": "src-1"'));
  });
}
