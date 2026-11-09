import 'package:pinyin/pinyin.dart';

/// 中文转拼音，进程内缓存。
///
/// 两处在用：本地检索（[initials] / [full]）和歌单排序（[sortKey]）。
/// 排序时 `compareTo` 比的是 UTF-16 码值，中文歌名在列表里等于随机顺序，
/// 换成拼音之后「按名称排序」才符合直觉。
class PinyinText {
  PinyinText._();

  static const int _maximumEntries = 20000;
  static final Map<String, String> _full = <String, String>{};
  static final Map<String, String> _initials = <String, String>{};

  /// 全拼，无分隔符：`周杰伦` → `zhoujielun`。
  static String full(String text) {
    final cached = _full[text];
    if (cached != null) return cached;
    _evictIfNeeded();
    return _full[text] = _convert(text, initials: false);
  }

  /// 首字母：`周杰伦` → `zjl`。
  static String initials(String text) {
    final cached = _initials[text];
    if (cached != null) return cached;
    _evictIfNeeded();
    return _initials[text] = _convert(text, initials: true);
  }

  /// 排序键：汉字取全拼，拉丁字母原样小写，于是中英混排也按读音顺序落位。
  static String sortKey(String text) => full(text);

  /// 按拼音比较两个字符串；拼音相同时退回原串，保证顺序稳定。
  static int compare(String a, String b) {
    final byPinyin = sortKey(a).compareTo(sortKey(b));
    return byPinyin != 0 ? byPinyin : a.compareTo(b);
  }

  /// 曲库整体换掉时调用，避免缓存里留着上一批歌名。
  static void clear() {
    _full.clear();
    _initials.clear();
  }

  /// 上限只做兜底：曲库上万首时整体清空，重建成本远低于维护 LRU。
  static void _evictIfNeeded() {
    if (_full.length >= _maximumEntries || _initials.length >= _maximumEntries) {
      _full.clear();
      _initials.clear();
    }
  }

  static String _convert(String text, {required bool initials}) {
    if (text.isEmpty) return '';
    final normalized = normalize(text);
    try {
      final converted = initials
          ? PinyinHelper.getShortPinyin(normalized)
          : PinyinHelper.getPinyin(normalized, separator: '');
      return _squeeze(converted);
    } on Object {
      return _squeeze(_convertPerCharacter(normalized, initials: initials));
    }
  }

  /// 生僻字没有拼音映射时 `getPinyin` 会抛异常，逐字降级保证整串还能用。
  static String _convertPerCharacter(String text, {required bool initials}) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      try {
        buffer.write(
          initials
              ? PinyinHelper.getShortPinyin(char)
              : PinyinHelper.getPinyin(char, separator: ''),
        );
      } on Object {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static String _squeeze(String value) => value.replaceAll(_whitespace, '');

  static final RegExp _whitespace = RegExp(r'\s+');
}

/// 全角转半角并小写：中文输入法敲出来的 `ＡＢＣ` 也要能命中或参与排序。
String normalize(String input) {
  if (input.isEmpty) return '';
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000) {
      buffer.write(' ');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().toLowerCase().trim();
}
