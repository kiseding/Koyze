/// 逐字歌词的动画解算。
///
/// 现在是"扫描线"：已唱部分亮起来，看起来是在读，不像是在唱。这里补上三件
/// 苹果音乐风格的细节，都是**纯函数**——只依赖「当前时间 + 这个词的时间窗」，
/// 不累加任何状态，所以拖动进度条、切后台回来都不会漂移：
///
/// 1. 词级上浮：每个词在自己的时间窗内抬起 `0.05em`；
/// 2. 长词强调：时长 ≥1s 的词逐字错峰放大 + 辉光 + 正弦浮动；
/// 3. 相邻词错开：由 [emphasisState] 的 `charDelay` 实现。
///
/// 曲线取自 AMLL（Apple Music Like Lyrics）的实现：前半段升到峰值、后半段
/// 落回，用两条三次贝塞尔拼出来。直接抄数值是因为这套参数是被大量真实歌曲
/// 调过的，自己调只会得到"动得不自然"。
library;

import 'dart:math' as math;

/// 三次贝塞尔缓动，等价于 CSS 的 `cubic-bezier(x1, y1, x2, y2)`。
class CubicBezierEasing {
  CubicBezierEasing(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// 二分求解 t，再取对应 y。精度 1e-4 对一帧内的亚像素位移足够。
  double transform(double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    var low = 0.0;
    var high = 1.0;
    var t = x;
    for (var i = 0; i < 12; i++) {
      t = (low + high) / 2;
      final estimate = _bezier(t, x1, x2);
      if (estimate < x) {
        low = t;
      } else {
        high = t;
      }
    }
    return _bezier(t, y1, y2);
  }

  static double _bezier(double t, double p1, double p2) {
    final inv = 1 - t;
    return 3 * inv * inv * t * p1 + 3 * inv * t * t * p2 + t * t * t;
  }
}

/// 强调缓动的分段中点。
const double kEmphasisMid = 0.5;

final CubicBezierEasing _bezIn = CubicBezierEasing(0.2, 0.4, 0.58, 1.0);
final CubicBezierEasing _bezOut = CubicBezierEasing(0.3, 0.0, 0.58, 1.0);
final CubicBezierEasing _easeOut = CubicBezierEasing(0.0, 0.0, 0.58, 1.0);

double _normalize(double x, double min, double max) {
  final v = (x - min) / (max - min);
  return v < 0 ? 0 : (v > 1 ? 1 : v);
}

/// 强调动画的缓动：前半段升到 1，后半段落回 0。
double emphasisEasing(double x, [double mid = kEmphasisMid]) {
  if (x < mid) return _bezIn.transform(_normalize(x, 0, mid));
  return 1 - _bezOut.transform(_normalize(x, mid, 1));
}

/// 单个词的浮动状态。
class WordMotion {
  const WordMotion({required this.offsetEm, required this.scale, required this.glowAlpha});

  static const WordMotion idle = WordMotion(
    offsetEm: 0,
    scale: 1,
    glowAlpha: 0,
  );

  /// 纵向偏移，单位 em（向上为负）。
  final double offsetEm;

  /// 缩放（强调用）。
  final double scale;

  /// 辉光强度 0~1。
  final double glowAlpha;

  @override
  bool operator ==(Object other) =>
      other is WordMotion &&
      other.offsetEm == offsetEm &&
      other.scale == scale &&
      other.glowAlpha == glowAlpha;

  @override
  int get hashCode => Object.hash(offsetEm, scale, glowAlpha);
}

/// 求解某个词在 [positionMs] 时的动画状态。
///
/// [wordStartMs] / [wordEndMs] 是这个词的时间窗；[isEmphasized] 决定是否叠加
/// 长词强调。所有时间都是相对**行首**的毫秒数，避免每帧做大数相减。
WordMotion solveWordMotion({
  required double positionMs,
  required double wordStartMs,
  required double wordEndMs,
  required bool isEmphasized,
  bool isBackground = false,
}) {
  final duration = math.max(1000.0, wordEndMs - wordStartMs);
  final sinceStart = positionMs - wordStartMs;

  // 词级上浮：ease-out 到 0.05em（背景人声加倍）。
  var offsetEm = 0.0;
  if (sinceStart > 0) {
    final progress = sinceStart >= duration
        ? 1.0
        : _easeOut.transform(sinceStart / duration);
    offsetEm = -(isBackground ? 0.1 : 0.05) * progress;
  }

  if (!isEmphasized) {
    return WordMotion(offsetEm: offsetEm, scale: 1, glowAlpha: 0);
  }

  // 长词强调：先按词时长推一个幅度，再叠加一段正弦浮动。
  var amount = duration / 2000;
  amount = amount > 1 ? math.sqrt(amount) : amount * amount * amount;
  amount = math.min(1.2, amount * 0.6);

  var glow = duration / 3000;
  glow = glow > 1 ? math.sqrt(glow) : glow * glow * glow;
  glow = math.min(0.8, glow * 0.5);

  final emphasized = emphasisEasing(
    (sinceStart / duration).clamp(0.0, 1.0),
  );
  final scale = 1 + emphasized * 0.1 * amount;
  final glowAlpha = emphasized * glow;

  final floatDuration = duration * 1.4;
  final floatT = ((sinceStart + 400) / floatDuration).clamp(0.0, 1.0);
  final sine = math.sin(floatT * math.pi) * (isBackground ? 2 : 1);

  return WordMotion(
    offsetEm: offsetEm - sine * 0.05,
    scale: scale,
    glowAlpha: glowAlpha,
  );
}

/// 判断一个词是否值得做强调。
///
/// 只对"唱得够久、字数不多"的词生效：短促的字放大反而像抽搐，长句放大又会
/// 糊到相邻行。
bool shouldEmphasize({
  required int durationMs,
  required String text,
  bool hasRuby = false,
}) {
  if (durationMs < 1000) return false;
  if (hasRuby) return true;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  // CJK 单字也算强调：中文歌词本来就是逐字推进的。
  if (_isCjk(trimmed)) return true;
  return trimmed.length > 1 && trimmed.length <= 7;
}

final RegExp _cjkRange = RegExp(
  r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af]',
);

bool _isCjk(String value) => _cjkRange.hasMatch(value);
