import 'package:flutter/foundation.dart';

import '../../../core/text/pinyin_text.dart';
import '../../player/domain/music_item.dart';

/// 本地曲库的检索：把歌名和歌手预先转成拼音，查询时按
/// 「完全相同 → 开头相同 → 包含 → 首拼 → 全拼 → 模糊子序列」六档打分。
///
/// 直接从 myune_music 的 `search_service.dart` / `pinyin_cache.dart` 借来思路：
/// 中文歌单里用户习惯敲 `zjl` 或 `zhoujielun` 找周杰伦，而 `contains` 只能命中原字。
/// 与上游的差别有三处：
///   * 拼音按整串转换，词组优先（`重庆` → `chongqing` 而不是 `zhongqing`）；
///   * 支持空格分词的「与」语义，`周杰伦 晴天` 两个词都要命中；
///   * 索引按曲库指纹缓存在内存里，重复搜索只做字符串比较。
class LocalSongSearchIndex {
  LocalSongSearchIndex._(this._entries, this._songs);

  final List<_IndexedSong> _entries;
  final List<MusicItem> _songs;

  int get length => _entries.length;

  /// 同步构建。曲库超过 [isolateThreshold] 首时调用方应改用 [build]，
  /// 免得拼音转换卡住当前帧。
  factory LocalSongSearchIndex.fromSongs(List<MusicItem> songs) {
    final rows = _buildRows([
      for (final song in songs) [song.name, song.singer, song.album],
    ]);
    return LocalSongSearchIndex._(_zip(songs, rows), List.unmodifiable(songs));
  }

  /// 曲库超过这个条数就换到 isolate 里构建。
  ///
  /// 拼音词典是几兆的常量表，首次使用要在堆上建索引；放在主 isolate 会卡住
  /// 首帧。小曲库（几十首）留在主线程，省掉一次 isolate 启动。
  static const int isolateThreshold = 120;

  static Future<LocalSongSearchIndex> build(List<MusicItem> songs) async {
    final payload = [
      for (final song in songs) [song.name, song.singer, song.album],
    ];
    final rows = songs.length <= isolateThreshold
        ? _buildRows(payload)
        : await compute(_buildRows, payload);
    return LocalSongSearchIndex._(_zip(songs, rows), List.unmodifiable(songs));
  }

  /// 排序后的命中结果；[limit] 为空时返回全部。
  List<LocalSongMatch> search(String rawQuery, {int? limit}) {
    final query = normalize(rawQuery);
    if (query.isEmpty) return const <LocalSongMatch>[];

    final tokens = query
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return const <LocalSongMatch>[];

    final matches = <_RankedMatch>[];
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      double total = 0;
      var weakest = LocalSongMatchType.exact;
      var matchedAll = true;
      for (final token in tokens) {
        final hit = entry.match(token);
        if (hit == null) {
          matchedAll = false;
          break;
        }
        total += hit.score;
        if (hit.type.index > weakest.index) weakest = hit.type;
      }
      if (!matchedAll) continue;

      // 整串命中歌名的排在多词拼出来的前面。
      if (entry.name == query) {
        total += 300;
      } else if (entry.name.startsWith(query)) {
        total += 120;
      }
      matches.add(
        _RankedMatch(
          song: _songs[i],
          score: total,
          type: weakest,
          order: i,
        ),
      );
    }

    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // 同分时短标题更可能是本人要找的：`晴天` 先于 `晴天 (Live)`。
      final byLength = a.song.name.length.compareTo(b.song.name.length);
      if (byLength != 0) return byLength;
      return a.order.compareTo(b.order);
    });

    final capped = limit == null || limit >= matches.length
        ? matches
        : matches.sublist(0, limit);
    return [
      for (final match in capped)
        LocalSongMatch(
          song: match.song,
          score: match.score,
          type: match.type,
        ),
    ];
  }

  static List<_IndexedSong> _zip(
    List<MusicItem> songs,
    List<List<String>> rows,
  ) {
    final entries = <_IndexedSong>[];
    for (var i = 0; i < songs.length; i++) {
      final row = rows[i];
      entries.add(
        _IndexedSong(
          name: row[0],
          singer: row[1],
          album: row[2],
          namePinyin: row[3],
          singerPinyin: row[4],
          nameInitials: row[5],
          singerInitials: row[6],
        ),
      );
    }
    return entries;
  }
}

/// 一条命中记录。[type] 是这条记录里最弱的那一档，用于 UI 上区分
/// 「这是拼音搜出来的」还是「只是字面像」。
class LocalSongMatch {
  const LocalSongMatch({
    required this.song,
    required this.score,
    required this.type,
  });

  final MusicItem song;
  final double score;
  final LocalSongMatchType type;
}

enum LocalSongMatchType { exact, prefix, contains, initials, pinyin, fuzzy }

class _RankedMatch {
  const _RankedMatch({
    required this.song,
    required this.score,
    required this.type,
    required this.order,
  });

  final MusicItem song;
  final double score;
  final LocalSongMatchType type;
  final int order;
}

class _Scored {
  const _Scored(this.score, this.type);

  final double score;
  final LocalSongMatchType type;
}

class _IndexedSong {
  const _IndexedSong({
    required this.name,
    required this.singer,
    required this.album,
    required this.namePinyin,
    required this.singerPinyin,
    required this.nameInitials,
    required this.singerInitials,
  });

  final String name;
  final String singer;
  final String album;
  final String namePinyin;
  final String singerPinyin;
  final String nameInitials;
  final String singerInitials;

  _Scored? match(String token) {
    _Scored? best;
    void consider(_Scored? hit) {
      if (hit != null && (best == null || hit.score > best!.score)) best = hit;
    }

    consider(_fieldScore(token, name, namePinyin, nameInitials));
    consider(_fieldScore(token, singer, singerPinyin, singerInitials));
    // 专辑只做字面匹配：专辑的拼音命中噪音太大，收益抵不上。
    consider(_plainScore(token, album));
    return best;
  }
}

List<List<String>> _buildRows(List<List<String>> payload) {
  final rows = <List<String>>[];
  for (final row in payload) {
    final name = row[0];
    final singer = row[1];
    final album = row[2];
    rows.add([
      normalize(name),
      normalize(singer),
      normalize(album),
      PinyinText.full(name),
      PinyinText.full(singer),
      PinyinText.initials(name),
      PinyinText.initials(singer),
    ]);
  }
  return rows;
}

bool _isLatinOnly(String text) => _latinOnlyPattern.hasMatch(text);

final RegExp _latinOnlyPattern = RegExp(r'^[a-z0-9]+$');

bool _isBoundary(String char) {
  final code = char.codeUnitAt(0);
  return code == 0x20 ||
      code == 0x2D ||
      code == 0x28 ||
      code == 0x5B ||
      code == 0x2F ||
      char == '·' ||
      char == '—';
}

_Scored? _plainScore(String token, String plain) {
  if (plain.isEmpty) return null;
  if (plain == token) return const _Scored(1000, LocalSongMatchType.exact);
  if (plain.startsWith(token)) {
    return const _Scored(900, LocalSongMatchType.prefix);
  }
  final index = plain.indexOf(token);
  if (index >= 0) {
    final atBoundary = index == 0 || _isBoundary(plain[index - 1]);
    return _Scored(
      atBoundary ? 830 : 790,
      LocalSongMatchType.contains,
    );
  }
  return null;
}

_Scored? _fieldScore(
  String token,
  String plain,
  String pinyin,
  String initials,
) {
  final direct = _plainScore(token, plain);
  if (direct != null) return direct;

  // 只有纯拉丁输入才可能是拼音：中文查询直接落到字面匹配就够了。
  if (!_isLatinOnly(token)) return null;
  // 单个字母的拼音匹配几乎等于把整个曲库倒出来，只保留字面命中。
  if (token.length < 2) return null;

  if (initials.isNotEmpty) {
    if (initials == token) {
      return const _Scored(770, LocalSongMatchType.initials);
    }
    if (initials.startsWith(token)) {
      return const _Scored(745, LocalSongMatchType.initials);
    }
    if (initials.contains(token)) {
      return const _Scored(705, LocalSongMatchType.initials);
    }
  }
  if (pinyin.isNotEmpty) {
    if (pinyin == token) {
      return const _Scored(685, LocalSongMatchType.pinyin);
    }
    if (pinyin.startsWith(token)) {
      return const _Scored(655, LocalSongMatchType.pinyin);
    }
    if (pinyin.contains(token)) {
      return const _Scored(625, LocalSongMatchType.pinyin);
    }
  }

  // 单字母的模糊匹配几乎会命中整个曲库，只在两个字符以上时才启用。
  if (token.length >= 2) {
    final fuzzyPlain = _fuzzyScore(token, plain);
    if (fuzzyPlain > 0) {
      return _Scored(400 + fuzzyPlain * 150, LocalSongMatchType.fuzzy);
    }
    final fuzzyPinyin = _fuzzyScore(token, pinyin);
    if (fuzzyPinyin > 0) {
      return _Scored(380 + fuzzyPinyin * 150, LocalSongMatchType.fuzzy);
    }
  }
  return null;
}

/// 子序列匹配，返回 0~1。连续命中、开头命中、覆盖率高都会加分。
double _fuzzyScore(String query, String target) {
  if (query.isEmpty || target.isEmpty || target.length < query.length) {
    return 0;
  }
  var queryIndex = 0;
  var lastMatch = -1;
  var raw = 0.0;
  for (var i = 0; i < target.length && queryIndex < query.length; i++) {
    if (target.codeUnitAt(i) != query.codeUnitAt(queryIndex)) continue;
    raw += 1;
    if (lastMatch >= 0) {
      final gap = i - lastMatch - 1;
      if (gap == 0) {
        raw += 1;
      } else if (gap <= 2) {
        raw += 0.5;
      }
    } else if (i == 0) {
      raw += 1;
    }
    lastMatch = i;
    queryIndex++;
  }
  if (queryIndex < query.length) return 0;
  final proximity = (raw / (query.length * 2)).clamp(0.0, 1.0);
  final coverage = (query.length / target.length).clamp(0.0, 1.0);
  return proximity * 0.7 + coverage * 0.3;
}

/// 索引缓存：按曲库指纹复用已算好的拼音。
///
/// 「本地」和「收藏」是两份曲库，来回切换时不该每次重算；曲库增删、
/// 重新刮削导致歌名变化时指纹会变，自然重建。
class LocalSongSearchCache {
  static const int _maximumIndexes = 4;

  final Map<int, LocalSongSearchIndex> _indexes = <int, LocalSongSearchIndex>{};
  final Map<int, Future<LocalSongSearchIndex>> _pending =
      <int, Future<LocalSongSearchIndex>>{};

  Future<LocalSongSearchIndex> indexFor(List<MusicItem> songs) async {
    final key = fingerprint(songs);
    final cached = _indexes[key];
    if (cached != null) return cached;
    // 同一批歌并发触发两次搜索时共用一次构建。
    final inFlight = _pending[key];
    if (inFlight != null) return inFlight;

    final future = LocalSongSearchIndex.build(songs);
    _pending[key] = future;
    try {
      final index = await future;
      _indexes[key] = index;
      if (_indexes.length > _maximumIndexes) {
        _indexes.remove(_indexes.keys.first);
      }
      return index;
    } finally {
      _pending.removeWhere((candidate, _) => candidate == key);
    }
  }

  void clear() {
    _indexes.clear();
    _pending.clear();
  }

  /// 曲库指纹：数量 + 每首歌的身份与文字内容。只做整数哈希，代价可控。
  static int fingerprint(List<MusicItem> songs) {
    var hash = songs.length;
    for (final song in songs) {
      hash = 0x7fffffff & (hash * 31 + song.identityKey.hashCode);
      hash = 0x7fffffff & (hash * 31 + song.name.hashCode);
      hash = 0x7fffffff & (hash * 31 + song.singer.hashCode);
    }
    return hash;
  }
}
