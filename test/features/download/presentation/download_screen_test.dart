import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../../support/source_text.dart';

void main() {
  test('download screen offers clear-failed action', () {
    final source = File(
      'lib/features/download/presentation/download_screen.dart',
    ).readAsStringSync();

    expect(source, contains("value == 'clear_failed'"));
    expect(source, contains('clearFailedTasks'));
    expect(
      readSource('lib/l10n/app_zh.arb'),
      contains('清理失败任务'),
    );
    expect(source, contains('DownloadStatus.failed'));
  });

  test('completed cleanup explicitly confirms audio file deletion', () {
    final source = File(
      'lib/features/download/presentation/download_screen.dart',
    ).readAsStringSync();

    expect(source, contains('deleteFinishedBody'));
    final strings = readSource('lib/l10n/app_zh.arb');
    expect(strings, contains('删除已完成下载'));
    expect(strings, contains('记录及其音频文件'));
    expect(strings, contains('此操作不可撤销'));
  });
}
