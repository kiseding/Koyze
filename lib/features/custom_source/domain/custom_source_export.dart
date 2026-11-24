// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// 自定义源的导出产物：一个可直接保存的 JSON 文件。
///
/// 单独抽出来是为了能测「导出再导入」的往返：界面上只负责把
/// [SourceExportFile.contents] 交给 `FilePicker.saveFile`，格式与文件名规则
/// 都在这里，不依赖平台通道。
library;

import 'dart:convert';

import 'custom_source.dart';

/// 待保存的导出文件。
class SourceExportFile {
  const SourceExportFile({required this.fileName, required this.contents});

  /// 建议文件名，已去掉路径分隔符等非法字符。
  final String fileName;

  /// 文件内容（缩进过的 JSON）。
  final String contents;

  /// UTF-8 字节。移动端 `saveFile` 必须把字节一起传给原生侧。
  List<int> get bytes => utf8.encode(contents);
}

/// 生成导出文件。
///
/// 结构就是 [CustomSource.toJson]，与 `CustomSourceService.importSource`
/// 接受的一致——导出的文件必须能被自己再导入，否则「导出」只是给人看的
/// 一段文本。
SourceExportFile buildSourceExport(CustomSource source) {
  final contents = const JsonEncoder.withIndent('  ').convert(source.toJson());
  return SourceExportFile(
    fileName: 'koyze_source_${safeSourceFileName(source.name)}.json',
    contents: contents,
  );
}

/// 去掉文件名里不能出现的字符。
///
/// 音源名常带 `/`（「A/B 音源」）和 `:`（「音源: 增强版」），这两个字符在
/// Android 与 Windows 上都会让保存直接失败。
String safeSourceFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'custom_source' : cleaned;
}
