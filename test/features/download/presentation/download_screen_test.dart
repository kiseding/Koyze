import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('download screen offers clear-failed action', () {
    final source = File(
      'lib/features/download/presentation/download_screen.dart',
    ).readAsStringSync();

    expect(source, contains("value == 'clear_failed'"));
    expect(source, contains('清理失败任务'));
    expect(source, contains('DownloadStatus.failed'));
  });

  test('completed cleanup explicitly confirms audio file deletion', () {
    final source = File(
      'lib/features/download/presentation/download_screen.dart',
    ).readAsStringSync();

    expect(source, contains('删除已完成下载'));
    expect(source, contains('记录及其音频文件'));
    expect(source, contains('此操作不可撤销'));
  });
}
