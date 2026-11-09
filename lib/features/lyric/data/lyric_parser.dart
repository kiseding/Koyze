import '../domain/lyric.dart';

class _ParsedLine {
  final Duration time;
  final String text;
  final List<LyricWord>? words;
  const _ParsedLine({required this.time, required this.text, this.words});
}

class LyricParser {
  /// 是否包含逐字时间标签（LRCX 或 QRC 风格）。
  static bool hasWordTiming(String raw) {
    if (raw.isEmpty) return false;
    // LRCX: <0,180>字 或 <12,34,0>
    if (RegExp(r'<-?\d+,-?\d+(?:,-?\d+)?>').hasMatch(raw)) return true;
    // QRC: <mm:ss.xx>字 或 <mm:ss.xxx,ddd>
    if (RegExp(r'<\d{2}:\d{2}\.\d{2,3}(?:,\d+)?>').hasMatch(raw)) return true;
    // Tencent QRC / Migu MRC uses at least two word timing tags per line.
    // A single parenthesized number pair is common in ordinary Kuwo lyrics and
    // must not switch the entire payload to the word-timed parser.
    if (RegExp(r'\[\d+,\d+\][^\n]*(?:\(\d+,\d+\)[^\n]*){2}').hasMatch(raw)) {
      return true;
    }
    return false;
  }

  static Lyrics parseLrc(String lrc) {
    final lines = <LyricLine>[];
    final List<String> lineList = lrc.split('\n');
    final offset = _parseOffset(lrc);
    final isKuwo = RegExp(r'\[kuwo\s*:', caseSensitive: false).hasMatch(lrc);
    final kuwoScale = _parseKuwoScale(lrc);

    final parsedLines = <_ParsedLine>[];
    for (final line in lineList) {
      final parsed = _parseLrcLine(line, isKuwo: isKuwo, kuwoScale: kuwoScale);
      if (parsed != null) {
        parsedLines.add(parsed);
      }
    }

    // 应用 [offset:±ms]；字级时间优先作为行时间（酷我行戳常为 00:00）
    final adjusted = parsedLines.map((p) {
      var t = p.time + offset;
      List<LyricWord>? words = p.words;
      if (words != null && words.isNotEmpty) {
        words = [
          for (final w in words)
            LyricWord(
              time: w.time + offset,
              text: w.text,
              duration: w.duration,
            ),
        ];
        final firstWord = words.first.time;
        // 行时间明显落后于首字（含行戳为 0）时以首字为准
        if (!isKuwo && firstWord > t) {
          t = firstWord;
        }
      }
      if (t < Duration.zero) t = Duration.zero;
      return _ParsedLine(time: t, text: p.text, words: words);
    }).toList();

    adjusted.sort((a, b) => a.time.compareTo(b.time));
    if (isKuwo) _clampKuwoWordsToNextLine(adjusted);

    int i = 0;
    while (i < adjusted.length) {
      final current = adjusted[i];
      String? translation;
      String? roman;

      // 同一时间戳连写的多行是「原文 / 翻译 / 音译」。日语歌词尤其常见：
      // 三行的行首时间戳完全一样，逐行读会变成三句同时高亮的重复歌词。
      // 第三行只有确实是拉丁转写（原文里有假名或谚文）才归为音译，
      // 否则保持原样另起一行，免得把第二种翻译错标成罗马音。
      var cursor = i + 1;
      while (cursor < adjusted.length &&
          adjusted[cursor].time == current.time &&
          adjusted[cursor].text != current.text) {
        if (translation == null) {
          translation = adjusted[cursor].text;
        } else if (roman == null &&
            _looksLikeRomanization(adjusted[cursor].text, current.text)) {
          roman = adjusted[cursor].text;
        } else {
          break;
        }
        cursor++;
      }
      i = cursor;

      lines.add(
        LyricLine(
          time: current.time,
          text: current.text,
          translation: translation,
          roman: roman,
          words: current.words,
        ),
      );
    }

    return Lyrics(raw: lrc, lines: lines);
  }

  /// 判断一行是不是原文的拉丁转写。
  ///
  /// 只看两点：原文里得有假名或谚文（中文歌的「罗马音」通常是英文翻译，
  /// 标错了反而会在音译开关打开时多出一行噪音），候选行得是纯 ASCII 字母。
  static bool _looksLikeRomanization(String candidate, String source) {
    if (!_hasKanaOrHangul(source)) return false;
    if (_hasKanaOrHangul(candidate)) return false;
    var letters = 0;
    for (final rune in candidate.runes) {
      final isAsciiLetter =
          (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);
      if (isAsciiLetter) {
        letters++;
        continue;
      }
      // 空格、撇号、连字符是转写里常见的分隔符。
      if (rune == 0x20 || rune == 0x27 || rune == 0x2D) continue;
      return false;
    }
    return letters >= 2;
  }

  static bool _hasKanaOrHangul(String text) {
    for (final rune in text.runes) {
      final isKana = rune >= 0x3040 && rune <= 0x30FF;
      final isHangul = rune >= 0xAC00 && rune <= 0xD7AF;
      final isHangulJamo = rune >= 0x1100 && rune <= 0x11FF;
      if (isKana || isHangul || isHangulJamo) return true;
    }
    return false;
  }

  static void _clampKuwoWordsToNextLine(List<_ParsedLine> lines) {
    for (var i = 0; i + 1 < lines.length; i++) {
      final words = lines[i].words;
      if (words == null || words.isEmpty) continue;
      final last = words.last;
      final duration = last.duration;
      if (duration == null || last.time + duration <= lines[i + 1].time) {
        continue;
      }
      final available = lines[i + 1].time - last.time;
      words[words.length - 1] = LyricWord(
        time: last.time,
        text: last.text,
        duration: available > Duration.zero ? available : Duration.zero,
      );
    }
  }

  /// LRC 全局偏移，如 `[offset:500]` / `[offset:-200]`
  static Duration _parseOffset(String raw) {
    final m = RegExp(
      r'\[offset\s*:\s*(-?\d+)\]',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m == null) return Duration.zero;
    final ms = int.tryParse(m.group(1) ?? '') ?? 0;
    return Duration(milliseconds: ms);
  }

  static (int, int)? _parseKuwoScale(String raw) {
    final match = RegExp(
      r'\[kuwo\s*:\s*([^\]]+)\]',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!.trim(), radix: 8);
    if (value == null) return null;
    final first = value ~/ 10;
    final second = value % 10;
    return first > 0 && second > 0 ? (first, second) : null;
  }

  static _ParsedLine? _parseLrcLine(
    String line, {
    required bool isKuwo,
    required (int, int)? kuwoScale,
  }) {
    // Kuwo LRCX can use a millisecond-only row marker such as `[12345]`.
    final RegExp timeRegExp = RegExp(
      r'\[(?:(\d{2}):(\d{2})\.?(\d{0,3})|(\d+))\]',
    );
    final matches = timeRegExp.allMatches(line);

    if (matches.isEmpty) {
      return null;
    }

    final match = matches.first;
    final int milliseconds;
    if (match.group(4) != null) {
      milliseconds = int.parse(match.group(4)!);
    } else {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final millisecondsStr = match.group(3) ?? '0';
      int fraction;
      if (millisecondsStr.isEmpty) {
        fraction = 0;
      } else if (millisecondsStr.length == 2) {
        fraction = int.parse(millisecondsStr) * 10;
      } else if (millisecondsStr.length == 1) {
        fraction = int.parse(millisecondsStr) * 100;
      } else {
        fraction = int.parse(millisecondsStr.substring(0, 3).padRight(3, '0'));
      }
      milliseconds = minutes * 60000 + seconds * 1000 + fraction;
    }

    final time = Duration(milliseconds: milliseconds);

    // 去掉全部行级时间标签后解析正文
    final body = line.replaceAll(timeRegExp, '').trim();
    if (body.isEmpty) return null;

    final words = isKuwo
        ? kuwoScale == null
              ? null
              : _parseKuwoWordTags(body, lineStart: time, scale: kuwoScale)
        : _parseWordTags(body, lineStart: time);
    if (words != null && words.isNotEmpty) {
      final text = words.map((w) => w.text).join();
      if (text.isEmpty) return null;
      return _ParsedLine(time: time, text: text, words: words);
    }

    // 无有效字级标签：剥离残留尖括号标签
    final text = body
        .replaceAll(RegExp(r'<-?\d+,-?\d+(?:,-?\d+)?>'), '')
        .replaceAll(RegExp(r'<\d{2}:\d{2}\.\d{2,3}(?:,\d+)?>'), '')
        .trim();
    if (text.isEmpty) return null;
    return _ParsedLine(time: time, text: text);
  }

  static List<LyricWord>? _parseKuwoWordTags(
    String body, {
    required Duration lineStart,
    required (int, int) scale,
  }) {
    final matches = RegExp(
      r'<(-?\d+),(-?\d+)(?:,-?\d+)?>([^<]*)',
    ).allMatches(body).toList();
    if (matches.isEmpty) return null;

    final words = <LyricWord>[];
    for (final match in matches) {
      final text = match.group(3) ?? '';
      if (text.isEmpty) continue;
      final first = int.parse(match.group(1)!);
      final second = int.parse(match.group(2)!);
      final relativeStart = ((first + second) / (scale.$1 * 2)).abs();
      final relativeEnd =
          relativeStart + ((first - second) / (scale.$2 * 2)).abs();
      final startMs = relativeStart.round();
      final endMs = relativeEnd.round();

      if (words.isNotEmpty) {
        final previous = words.last;
        final previousStart =
            previous.time.inMilliseconds - lineStart.inMilliseconds;
        final previousEnd =
            previousStart + (previous.duration?.inMilliseconds ?? 0);
        if (startMs < previousEnd) {
          final adjustedStart = previousStart.clamp(0, startMs);
          words[words.length - 1] = LyricWord(
            time: lineStart + Duration(milliseconds: adjustedStart),
            text: previous.text,
            duration: Duration(milliseconds: startMs - adjustedStart),
          );
        }
      }

      words.add(
        LyricWord(
          time: lineStart + Duration(milliseconds: startMs),
          text: text,
          duration: endMs > startMs
              ? Duration(milliseconds: endMs - startMs)
              : null,
        ),
      );
    }
    return words.isEmpty ? null : words;
  }

  /// 解析 LRCX / QRC 字级标签。
  ///
  /// 支持：
  /// - LRCX 相对：`词<0,180>语<180,200>`（start/duration 毫秒，相对行起点）
  /// - LRCX 前置：`<0,180>词<180,200>语`
  /// - QRC 时钟：`<00:12.34>字` 或 `<00:12.34,180>字`
  /// - 绝对毫秒：`<12100,180>字`（start 很大时按绝对时间）
  static List<LyricWord>? _parseWordTags(
    String body, {
    required Duration lineStart,
  }) {
    // QRC 时钟格式
    final qrcClock = RegExp(r'<(\d{2}):(\d{2})\.(\d{2,3})(?:,(\d+))?>([^<]*)');
    if (qrcClock.hasMatch(body)) {
      final words = <LyricWord>[];
      for (final m in qrcClock.allMatches(body)) {
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        final ms = int.parse(m.group(3)!.padRight(3, '0'));
        final durMs = m.group(4) != null ? int.tryParse(m.group(4)!) : null;
        final text = m.group(5) ?? '';
        if (text.isEmpty) continue;
        words.add(
          LyricWord(
            time: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: ms,
            ),
            text: text,
            duration: durMs != null ? Duration(milliseconds: durMs) : null,
          ),
        );
      }
      return words.isEmpty ? null : words;
    }

    // LRCX / 绝对毫秒：<start,duration[,extra]>text
    final lrcx = RegExp(r'<(-?\d+),(-?\d+)(?:,-?\d+)?>([^<]*)');
    if (!lrcx.hasMatch(body)) return null;

    final words = <LyricWord>[];
    final matches = lrcx.allMatches(body).toList();
    if (matches.isEmpty) return null;

    // yrc：正文以非 < 开头，且整体为「字<start,dur>」重复（字在标签前）
    final yrcLike =
        !body.trimLeft().startsWith('<') &&
        RegExp(
          r'^(?:[^<]+<-?\d+,-?\d+(?:,-?\d+)?>)+\s*[^<]*$',
        ).hasMatch(body.trim());

    if (yrcLike) {
      final yrc = RegExp(r'([^<]+)<(-?\d+),(-?\d+)(?:,-?\d+)?>');
      final yrcMatches = yrc.allMatches(body).toList();
      for (final m in yrcMatches) {
        final text = (m.group(1) ?? '').trim();
        final startMs = int.tryParse(m.group(2) ?? '') ?? 0;
        final durMs = int.tryParse(m.group(3) ?? '') ?? 0;
        if (text.isEmpty) continue;
        words.add(
          _wordFromOffset(
            lineStart: lineStart,
            startMs: startMs,
            durMs: durMs,
            text: text,
          ),
        );
      }
      // 末尾无标签的残余字
      if (yrcMatches.isNotEmpty) {
        final tail = body.substring(yrcMatches.last.end).trim();
        if (tail.isNotEmpty && words.isNotEmpty) {
          final prev = words.last;
          final start = prev.time + (prev.duration ?? Duration.zero);
          words.add(LyricWord(time: start, text: tail));
        }
      }
      return words.isEmpty ? null : words;
    }

    for (final m in matches) {
      final startMs = int.tryParse(m.group(1) ?? '') ?? 0;
      final durMs = int.tryParse(m.group(2) ?? '') ?? 0;
      final text = m.group(3) ?? '';
      if (text.isEmpty) continue;
      words.add(
        _wordFromOffset(
          lineStart: lineStart,
          startMs: startMs,
          durMs: durMs,
          text: text,
        ),
      );
    }
    return words.isEmpty ? null : words;
  }

  static LyricWord _wordFromOffset({
    required Duration lineStart,
    required int startMs,
    required int durMs,
    required String text,
  }) {
    // Generic LRCX/YRC labels are relative to the line. Large values used by
    // converted formats may already be absolute media timestamps.
    final lineMs = lineStart.inMilliseconds;
    final Duration time;
    if (startMs >= lineMs && startMs > 10000) {
      time = Duration(milliseconds: startMs);
    } else {
      time = lineStart + Duration(milliseconds: startMs < 0 ? 0 : startMs);
    }
    return LyricWord(
      time: time,
      text: text,
      duration: durMs > 0 ? Duration(milliseconds: durMs) : null,
    );
  }

  /// 把并列的翻译 / 音译歌词挂到主歌词行上。
  ///
  /// 网易把三者放在同一次响应的三个字段里（`lrc` / `tlyric` / `romalrc`），
  /// 时间戳各自独立、不保证逐字对齐。这里按时间戳匹配：先精确命中，再退到
  /// 最近的一行（容差 80ms）——两者对不上的时候宁可少显示一行，也不要把
  /// 上一句的翻译挂到这一句上。
  static Lyrics attachParallelText(
    Lyrics lyrics, {
    String? translation,
    String? roman,
  }) {
    final translationMap = _timeMap(translation);
    final romanMap = _timeMap(roman);
    if (translationMap.isEmpty && romanMap.isEmpty) return lyrics;

    final lines = [
      for (final line in lyrics.lines)
        line.copyWith(
          translation:
              _lookupNearest(translationMap, line.time) ?? line.translation,
          roman: _lookupNearest(romanMap, line.time),
        ),
    ];
    return Lyrics(raw: lyrics.raw, lines: lines);
  }

  /// LRC → 时间戳（毫秒）到文本的映射。全局 `[offset:]` 一并应用，
  /// 否则主歌词平移了、翻译没平移，两行会错开。
  static Map<int, String> _timeMap(String? lrc) {
    if (lrc == null || lrc.trim().isEmpty) return const {};
    final offsetMs = _parseOffset(lrc).inMilliseconds;
    final result = <int, String>{};
    final regExp = RegExp(r'\[(\d{2}):(\d{2})[.:](\d{2,3})\]');
    for (final raw in lrc.split('\n')) {
      final match = regExp.firstMatch(raw);
      if (match == null) continue;
      final body = raw.replaceAll(regExp, '').trim();
      if (body.isEmpty) continue;
      final fraction = match.group(3)!.padRight(3, '0').substring(0, 3);
      final ms =
          int.parse(match.group(1)!) * 60000 +
          int.parse(match.group(2)!) * 1000 +
          int.parse(fraction) +
          offsetMs;
      if (ms < 0) continue;
      result[ms] = body;
    }
    return result;
  }

  static String? _lookupNearest(Map<int, String> map, Duration time) {
    if (map.isEmpty) return null;
    final key = time.inMilliseconds;
    final exact = map[key];
    if (exact != null) return exact;
    var bestDelta = 81;
    String? best;
    for (final entry in map.entries) {
      final delta = (entry.key - key).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = entry.value;
      }
    }
    return best;
  }

  static Lyrics parseQrc(String qrc) {
    final content = _extractQrcContent(qrc);
    final lines = <LyricLine>[];
    final List<String> lineList = content.split('\n');
    final offset = _parseOffset(content);

    for (final line in lineList) {
      final parsed = _parseQrcLine(line, offset: offset);
      if (parsed != null) {
        lines.add(parsed);
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return Lyrics(raw: qrc, lines: lines);
  }

  static String _extractQrcContent(String raw) {
    const marker = 'LyricContent="';
    final start = raw.indexOf(marker);
    if (start < 0) return raw;
    final contentStart = start + marker.length;
    final end = raw.indexOf('"', contentStart);
    if (end < 0) return raw.substring(contentStart);
    return raw.substring(contentStart, end);
  }

  static LyricLine? _parseQrcLine(
    String line, {
    Duration offset = Duration.zero,
  }) {
    final tencentMatch = RegExp(
      r'^\[\s*(\d+)\s*,\s*(\d+)\s*\]',
    ).firstMatch(line);
    if (tencentMatch != null) {
      final startMs = int.parse(tencentMatch.group(1)!);
      var time = Duration(milliseconds: startMs) + offset;
      if (time < Duration.zero) time = Duration.zero;
      final textPart = line.substring(tencentMatch.end);
      final wordsRaw = _parseTencentWordTags(textPart);
      if (wordsRaw != null && wordsRaw.isNotEmpty) {
        final words = [
          for (final w in wordsRaw)
            LyricWord(
              // 腾讯 QRC 的字 start 是绝对毫秒（从歌曲开始），直接用 w.time
              //（可叠加 [offset:] 全局偏移）。不要加行 time，否则双重加导致
              // 逐字高亮时间整体偏移、唱几句后逐字消失。
              time: w.time + offset,
              text: w.text,
              duration: w.duration,
            ),
        ];
        final text = words.map((w) => w.text).join();
        if (text.isNotEmpty) {
          return LyricLine(time: time, text: text, words: words);
        }
      }
      final plain = textPart.replaceAll(RegExp(r'\(\d+,\d+\)'), '').trim();
      if (plain.isEmpty) return null;
      return LyricLine(time: time, text: plain);
    }

    final RegExp timeRegExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');
    final match = timeRegExp.firstMatch(line);
    if (match == null) return null;

    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final milliseconds = int.parse(match.group(3)!.padRight(3, '0'));
    var time =
        Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        ) +
        offset;
    if (time < Duration.zero) time = Duration.zero;

    final textPart = line.substring(match.end);
    final wordsRaw = _parseWordTags(textPart, lineStart: time - offset);
    if (wordsRaw == null || wordsRaw.isEmpty) {
      final plain = textPart.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (plain.isEmpty) return null;
      return LyricLine(time: time, text: plain);
    }

    final words = [
      for (final w in wordsRaw)
        LyricWord(time: w.time + offset, text: w.text, duration: w.duration),
    ];
    if (words.first.time > time) {
      time = words.first.time;
    }
    final text = words.map((w) => w.text).join();
    return LyricLine(time: time, text: text, words: words);
  }

  /// Parses Tencent QRC / Migu MRC word tags: text(start,dur)text2(start2,dur2).
  /// start is absolute milliseconds from the beginning of the song.
  static List<LyricWord>? _parseTencentWordTags(String body) {
    final reg = RegExp(r'([^()]*?)\((\d+),(\d+)\)');
    final matches = reg.allMatches(body).toList();
    if (matches.isEmpty) return null;

    final words = <LyricWord>[];
    for (final m in matches) {
      final text = m.group(1) ?? '';
      if (text.isEmpty) continue;
      final startMs = int.parse(m.group(2)!);
      final durMs = int.parse(m.group(3)!);
      words.add(
        LyricWord(
          time: Duration(milliseconds: startMs),
          text: text,
          duration: durMs > 0 ? Duration(milliseconds: durMs) : null,
        ),
      );
    }
    return words.isEmpty ? null : words;
  }
}
