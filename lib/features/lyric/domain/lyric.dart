class LyricLine {
  final Duration time;
  final String text;
  final String? translation;

  /// 音译（罗马音）行。日语歌靠它才读得出读音，网易由 `romalrc` 提供。
  final String? roman;
  final List<LyricWord>? words;

  const LyricLine({
    required this.time,
    required this.text,
    this.translation,
    this.roman,
    this.words,
  });

  bool get hasWordTiming => words != null && words!.isNotEmpty;

  LyricLine copyWith({
    Duration? time,
    String? text,
    String? translation,
    String? roman,
    List<LyricWord>? words,
  }) {
    return LyricLine(
      time: time ?? this.time,
      text: text ?? this.text,
      translation: translation ?? this.translation,
      roman: roman ?? this.roman,
      words: words ?? this.words,
    );
  }
}

/// 一次歌词请求的完整结果。
///
/// 主歌词、翻译、音译在平台接口里是**三个并列字段**（网易的 `lrc` /
/// `tlyric` / `romalrc`），而不是一段能靠时间戳拼回去的文本。以前只有
/// `String?` 一个返回值，翻译和音译在出口处就被丢掉了，播放页自然只剩原文。
/// 保留成一个对象，才能让下层决定「取哪些、怎么合并」而不必改平台接口。
class LyricPayload {
  const LyricPayload({required this.main, this.translation, this.roman});

  /// 主歌词原文（可能含逐字标签）。
  final String main;

  /// 翻译歌词，LRC 文本。
  final String? translation;

  /// 音译（罗马音）歌词，LRC 文本。
  final String? roman;

  bool get hasExtras =>
      (translation != null && translation!.trim().isNotEmpty) ||
      (roman != null && roman!.trim().isNotEmpty);
}

class LyricWord {
  final Duration time;
  final String text;
  /// 该字/词持续时间；无则按到下一字或行结束估算。
  final Duration? duration;

  const LyricWord({
    required this.time,
    required this.text,
    this.duration,
  });
}

class Lyrics {
  final String raw;
  final List<LyricLine> lines;

  const Lyrics({
    required this.raw,
    required this.lines,
  });

  factory Lyrics.empty() => const Lyrics(raw: '', lines: []);

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  int getCurrentLineIndex(Duration position) {
    if (lines.isEmpty) return -1;
    // 尚未到首句
    if (position < lines.first.time) return -1;

    int low = 0;
    int high = lines.length - 1;
    int result = 0;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].time <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return result;
  }

  LyricLine? getCurrentLine(Duration position) {
    final index = getCurrentLineIndex(position);
    if (index >= 0 && index < lines.length) {
      return lines[index];
    }
    return null;
  }

  /// 当前行内已唱到的字索引；-1 表示尚未到该行或无字级时间。
  int getCurrentWordIndex(Duration position, int lineIndex) {
    if (lineIndex < 0 || lineIndex >= lines.length) return -1;
    final line = lines[lineIndex];
    final words = line.words;
    if (words == null || words.isEmpty) return -1;
    if (position < line.time) return -1;

    int active = -1;
    for (var i = 0; i < words.length; i++) {
      if (words[i].time <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  /// 当前活动字的填充比例 0.0–1.0（KTV 流式）。
  double getWordFillProgress(Duration position, int lineIndex, int wordIndex) {
    if (lineIndex < 0 || lineIndex >= lines.length) return 0;
    final line = lines[lineIndex];
    final words = line.words;
    if (words == null || wordIndex < 0 || wordIndex >= words.length) return 0;

    final word = words[wordIndex];
    if (position <= word.time) return 0;

    Duration dur = word.duration ?? Duration.zero;
    if (dur <= Duration.zero) {
      if (wordIndex + 1 < words.length) {
        dur = words[wordIndex + 1].time - word.time;
      } else if (lineIndex + 1 < lines.length) {
        dur = lines[lineIndex + 1].time - word.time;
      } else {
        dur = const Duration(milliseconds: 400);
      }
    }
    if (dur <= Duration.zero) return 1;

    final elapsed = position - word.time;
    final p = elapsed.inMicroseconds / dur.inMicroseconds;
    if (p <= 0) return 0;
    if (p >= 1) return 1;
    return p;
  }
}
