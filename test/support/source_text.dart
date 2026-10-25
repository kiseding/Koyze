/// 读取源码文件用于结构断言时的公共工具。
///
/// ## 为什么会有这个文件
///
/// 仓库里有一批「结构护栏」测试：它们不断言运行时行为，而是断言某段源码里
/// 仍然存在某个构造（例如 `resizeToAvoidBottomInset: false`、`barrierDismissible: true`）。
///
/// 这类测试本身是有争议的——它们对重命名敏感、对真实回归迟钝。已经在
/// `docs/adr/0005-test-strategy.md` 里记录了取舍：**能改成行为测试的一律改，
/// 剩下的是"跨文件一致性"和"构建配置契约"，这两类没有行为可测，只能读文件。**
///
/// ## 这个工具解决的问题
///
/// `File.readAsStringSync()` 在 Windows 上会返回 CRLF（因为 git 的
/// `core.autocrlf`），而测试里写的是 `contains('...\n...')`。
/// 结果是同一份代码在 Linux CI 上通过、在 Windows 开发机上必然失败。
///
/// 修复分两层：
/// 1. `.gitattributes` 强制 Dart 源码以 LF 检出（根治）
/// 2. 这个工具再把换行统一成 LF（防御，覆盖已经检出的仓库）
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show fail;

/// 读文件并把换行统一成 LF。
///
/// 所有做结构断言的测试都应该用它，而不是直接 `readAsStringSync()`。
String readSource(String path) {
  final raw = File(path).readAsStringSync();
  // 先处理 CRLF，再单独处理裸 CR（老式 Mac 换行）。
  return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// 断言文件存在且非空，并返回归一化后的内容。
///
/// 路径写错时给出比 `FileSystemException` 更容易定位的失败信息。
String readSourceOrFail(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('被测源码文件不存在: $path（测试与实现路径不一致？）');
  }
  final content = readSource(path);
  if (content.trim().isEmpty) {
    fail('被测源码文件为空: $path');
  }
  return content;
}
