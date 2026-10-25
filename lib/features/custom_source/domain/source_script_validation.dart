class SourceScriptHeader {
  const SourceScriptHeader(this.values);

  final Map<String, String> values;

  String? operator [](String key) => values[key.toLowerCase()];
}

SourceScriptHeader? parseSourceScriptHeader(String script) {
  // Windows 编辑器 / GitHub 网页上传的脚本普遍是 CRLF。Dart 的 `.` 不匹配
  // `\r`，`$` 在非多行模式下也只匹配串尾，于是 `@name xxx\r` 整行匹配失败，
  // 头部解析出空 name、导入被误判为「脚本头部无效」。
  // 统一换行后再切行，CRLF / LF / 裸 CR 都能正确解析。
  final trimmed = script.trimLeft();
  if (!trimmed.startsWith('/*')) return null;
  final end = trimmed.indexOf('*/', 2);
  if (end < 0) return null;
  final header = trimmed.substring(0, end + 2).replaceAll('\r\n', '\n');
  final values = <String, String>{};
  for (final rawLine in header.split(RegExp(r'[\r\n]'))) {
    final line = rawLine.trimRight();
    final match = RegExp(
      r'@([A-Za-z][\w-]*)\s+(.+?)(?:\s*\*/)?$',
    ).firstMatch(line);
    if (match != null) {
      final value = match.group(2)!.trim();
      if (value.isNotEmpty) {
        values[match.group(1)!.toLowerCase()] = value;
      }
    }
  }
  return SourceScriptHeader(values);
}

bool isValidSourceScript(String script) {
  final header = parseSourceScriptHeader(script);
  return header != null && (header['name']?.isNotEmpty ?? false);
}
