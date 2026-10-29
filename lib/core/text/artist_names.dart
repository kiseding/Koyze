/// 把一个「歌手」字段拆成多个名字。
///
/// 只在明确的分隔符上拆：`;` `；` `、` `|` `｜`、两侧带空格的 `/`，以及
/// `feat.` / `ft.` / `featuring` 这类合作标记。**不拆单独的 `/` 和 `&`**——
/// AC/DC、Simon & Garfunkel 会被拆坏，而这两种写法比「A/B 合唱」更常见。
///
/// 返回结果保留原始大小写与顺序，去重但不去空白以外的字符。
List<String> splitArtistNames(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const <String>[];
  final normalized = text
      .replaceAll(
        RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+', caseSensitive: false),
        ';',
      )
      .replaceAll(RegExp(r'\s+/\s+'), ';')
      .replaceAll(RegExp(r'[；、|｜]'), ';');
  final seen = <String>{};
  final names = <String>[];
  for (final part in normalized.split(';')) {
    final name = part.trim();
    if (name.isEmpty) continue;
    if (!seen.add(name.toLowerCase())) continue;
    names.add(name);
  }
  return names.isEmpty ? <String>[text] : names;
}

/// 统计、筛选这类「按人聚合」的场景用：单歌手时返回原字符串，避免多一层。
List<String> artistNamesOf(String raw) => splitArtistNames(raw);
