/// One row the settings search can match against.
///
/// Deliberately free of Flutter types: the ranking is plain data in, plain
/// data out, so it can be tested without a widget tree.
abstract interface class SettingsSearchTarget {
  /// Section header the row sits under, e.g. "Playback".
  String get sectionLabel;

  String get title;

  String get subtitle;

  /// Words a user may type instead of the row's own copy — "night" for dark
  /// mode, "flac" for audio quality. Never rendered.
  List<String> get keywords;
}

/// Filters [items] by [query], best match first.
///
/// The query is split on whitespace and **every** token has to hit something,
/// so "dark theme" narrows instead of widening. Matches are ranked by where
/// the token lands — the title beats a keyword, which beats the subtitle — and
/// ties keep the page order, which is the order rows appear in Settings.
///
/// Matching ignores case and punctuation, so `wifi` finds "仅 Wi-Fi" and
/// `flac` finds "无损 (FLAC)".
List<T> searchSettings<T extends SettingsSearchTarget>(
  List<T> items,
  String query,
) {
  final tokens = _tokenize(query);
  if (tokens.isEmpty) return List<T>.of(items);

  final scored = <_Scored<T>>[];
  for (var index = 0; index < items.length; index++) {
    final score = _score(items[index], tokens);
    if (score > 0) scored.add(_Scored<T>(items[index], score, index));
  }
  scored.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    return a.index.compareTo(b.index);
  });
  return [for (final entry in scored) entry.item];
}

class _Scored<T> {
  const _Scored(this.item, this.score, this.index);

  final T item;
  final int score;
  final int index;
}

// A token in the title is worth more than the same token in a keyword: the
// first row of results should be the one literally named after the query.
const int _titleExact = 120;
const int _titlePrefix = 100;
const int _titleContains = 80;
const int _keywordExact = 70;
const int _keywordPrefix = 60;
const int _keywordContains = 50;
const int _sectionContains = 30;
const int _subtitleContains = 20;

int _score(SettingsSearchTarget item, List<String> tokens) {
  final title = _fold(item.title);
  final subtitle = _fold(item.subtitle);
  final section = _fold(item.sectionLabel);
  final keywords = <String>[
    for (final keyword in item.keywords) _fold(keyword),
  ];

  var total = 0;
  for (final token in tokens) {
    var best = 0;
    if (title == token) {
      best = _titleExact;
    } else if (title.startsWith(token)) {
      best = _titlePrefix;
    } else if (title.contains(token)) {
      best = _titleContains;
    }
    for (final keyword in keywords) {
      final hit = keyword == token
          ? _keywordExact
          : keyword.startsWith(token)
          ? _keywordPrefix
          : keyword.contains(token)
          ? _keywordContains
          : 0;
      if (hit > best) best = hit;
    }
    if (best < _subtitleContains && subtitle.contains(token)) {
      best = _subtitleContains;
    }
    if (best < _sectionContains && section.contains(token)) {
      best = _sectionContains;
    }
    // One unmatched token rejects the row: "dark theme" must not return every
    // row that merely belongs to the appearance section.
    if (best == 0) return 0;
    total += best;
  }
  return total;
}

List<String> _tokenize(String query) {
  final tokens = <String>[];
  for (final part in query.split(RegExp(r'\s+'))) {
    final token = _fold(part);
    if (token.isNotEmpty) tokens.add(token);
  }
  return tokens;
}

/// Lowercase, then drop everything that is not a letter, digit or Han
/// character. Runs of separators become invisible instead of blocking a
/// match, which is what lets `wifi` find "仅 Wi-Fi".
final RegExp _noise = RegExp(r'[^0-9a-z\u4e00-\u9fff]+');

String _fold(String value) =>
    value.toLowerCase().replaceAll(_noise, '');
