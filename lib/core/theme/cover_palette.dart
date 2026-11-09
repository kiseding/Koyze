/// 从封面里取一组可用于界面的颜色。
///
/// 目标不是"还原图片配色"，而是"给界面找一支能用的一眼能认出来的颜色"：
/// 封面上的主色往往饱和过高或过暗，直接铺到按钮上会看不清字，所以取完还要
/// 夹到可用区间。取色失败、封面是纯黑白、网络没拿到图，都返回 null，调用方
/// 退回用户手选的主题色。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../widgets/artwork_disk_cache.dart';

/// 一组派生自封面的颜色。
@immutable
class CoverPalette {
  const CoverPalette({
    required this.accent,
    required this.secondary,
    required this.background,
  });

  /// 主色：主题强调色用它。
  final Color accent;

  /// 次色：渐变、辉光、第二层装饰用它。
  final Color secondary;

  /// 背景基色：播放页的深色底用它，避免纯黑。
  final Color background;

  @override
  bool operator ==(Object other) =>
      other is CoverPalette &&
      other.accent == accent &&
      other.secondary == secondary &&
      other.background == background;

  @override
  int get hashCode => Object.hash(accent, secondary, background);
}

/// 封面取色服务。
///
/// 解码尺寸固定 48×48：再小色相会糊，再大对结果没有帮助却要多算几十万像素。
/// 一张封面只算一次，按 URL 缓存；同一 URL 并发请求合并成一次计算。
class CoverPaletteService {
  CoverPaletteService({
    Future<Uint8List?> Function(String url)? bytesLoader,
    DateTime Function()? clock,
  }) : _bytesLoader = bytesLoader ?? _defaultLoader,
       _clock = clock ?? DateTime.now;

  static final CoverPaletteService instance = CoverPaletteService();

  /// 取色失败后多久才允许为同一张封面重新发请求。
  ///
  /// 不能像以前那样把失败永久记住：换歌的瞬间封面常常还没下载完，一次
  /// 抢先的失败会让这首歌整首都用不上封面颜色；可完全不记又会在坏图上
  /// 反复发请求。取一个能兜住换歌窗口、又不会打爆 CDN 的折中值。
  static const Duration failureCooldown = Duration(seconds: 20);

  final Future<Uint8List?> Function(String url) _bytesLoader;
  final DateTime Function() _clock;
  final Map<String, CoverPalette> _cache = {};
  final Map<String, Future<CoverPalette?>> _inflight = {};

  /// 失败时间戳。成功后从这张表里删掉，避免和 [_cache] 两套状态打架。
  final Map<String, DateTime> _failedAt = {};
  final Map<String, int> _cacheOrder = {};
  int _tick = 0;

  /// 缓存上限。封面 URL 带尺寸参数，同一首歌可能有多套，留 64 条足够。
  static const int _maxEntries = 64;

  /// 直接读封面字节。
  ///
  /// 优先命中磁盘/内存缓存（列表、播放页、锁屏封面都会往这里写）；没命中
  /// 就自己下载一次并落盘——换歌时取色往往比播放页解封面更早，只读缓存
  /// 会一直"取不到颜色"，表现就是主题色只有开启那一刻生效。
  static Future<Uint8List?> _defaultLoader(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.scheme == 'file') {
      // 本地音乐的封面是落盘文件，没有 HTTP 可取。
      try {
        final bytes = await File(uri.toFilePath()).readAsBytes();
        return bytes.isEmpty ? null : bytes;
      } catch (_) {
        return null;
      }
    }
    final cached = await ArtworkDiskCache.instance.bytesForUrl(url);
    if (cached != null && cached.isNotEmpty) return cached;
    final file = await ArtworkDiskCache.instance.ensureLocalFile(url);
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// 取 [url] 的调色板；不可用返回 null。
  ///
  /// [ignoreFailureCooldown] 给"同一次播放里的补试"用：调用方知道自己在
  /// 重试同一首歌，应该允许穿过冷却期再试一次。
  Future<CoverPalette?> paletteFor(
    String url, {
    bool ignoreFailureCooldown = false,
  }) async {
    if (url.isEmpty) return null;
    final cached = _cache[url];
    if (cached != null) return cached;
    if (!ignoreFailureCooldown && _isCoolingDown(url)) return null;
    final pending = _inflight[url];
    if (pending != null) return pending;

    final future = _compute(url).then((palette) {
      _remember(url, palette);
      return palette;
    }).whenComplete(() {
      _inflight.remove(url);
    });
    _inflight[url] = future;
    return future;
  }

  /// 同步读缓存，用于首帧就想要颜色的场景（命中不了就返回 null）。
  CoverPalette? cachedFor(String url) => _cache[url];

  bool _isCoolingDown(String url) {
    final failedAt = _failedAt[url];
    if (failedAt == null) return false;
    if (_clock().difference(failedAt) < failureCooldown) return true;
    _failedAt.remove(url);
    return false;
  }

  void _remember(String url, CoverPalette? palette) {
    if (palette == null) {
      // 失败只记时间戳，冷却期过后换个时间点或补试仍有机会成功。
      _failedAt[url] = _clock();
      if (_failedAt.length > _maxEntries * 2) _failedAt.clear();
      return;
    }
    _failedAt.remove(url);
    _cache[url] = palette;
    _cacheOrder[url] = ++_tick;
    if (_cache.length > _maxEntries) {
      // 淘汰最早写入的一条，不做 LRU 记账——这里没有"访问热点"可言。
      String? oldest;
      var oldestTick = 1 << 62;
      for (final entry in _cacheOrder.entries) {
        if (entry.value < oldestTick) {
          oldestTick = entry.value;
          oldest = entry.key;
        }
      }
      if (oldest != null) {
        _cache.remove(oldest);
        _cacheOrder.remove(oldest);
      }
    }
  }

  Future<CoverPalette?> _compute(String url) async {
    try {
      final bytes = await _bytesLoader(url);
      if (bytes == null || bytes.isEmpty) return null;
      final pixels = await _decodeSquare(bytes, 48);
      if (pixels == null) return null;
      return _buildPalette(pixels.rgba, pixels.width, pixels.height);
    } catch (_) {
      // 取色是锦上添花，任何失败都只是退回默认主题色。
      return null;
    }
  }

  static Future<_Pixels?> _decodeSquare(Uint8List bytes, int size) async {
    // 用目标尺寸解码，避免把 1000×1000 的封面整张展开。
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: size,
      targetHeight: size,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null) return null;
        return _Pixels(
          data.buffer.asUint8List(),
          image.width,
          image.height,
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  static CoverPalette? _buildPalette(Uint8List rgba, int width, int height) {
    final count = width * height;
    if (count == 0 || rgba.length < count * 4) return null;

    // 按色相分 12 个桶累积权重，权重 = 饱和度² × 明度可用性。
    // 用饱和度平方是为了让"灰蒙蒙一片"的封面也能选出一个还能看的色相，
    // 同时不让大量低饱和背景把票数全吃掉。
    final weightPerBucket = List<double>.filled(12, 0);
    final rSum = List<double>.filled(12, 0);
    final gSum = List<double>.filled(12, 0);
    final bSum = List<double>.filled(12, 0);

    for (var i = 0; i < count; i++) {
      final offset = i * 4;
      final a = rgba[offset + 3];
      if (a < 40) continue;
      final r = rgba[offset] / 255.0;
      final g = rgba[offset + 1] / 255.0;
      final b = rgba[offset + 2] / 255.0;

      final maxC = math.max(r, math.max(g, b));
      final minC = math.min(r, math.min(g, b));
      final lightness = (maxC + minC) / 2;
      // 接近纯黑/纯白/深灰的像素对"认色"没有帮助。
      if (lightness < 0.12 || lightness > 0.93) continue;
      final delta = maxC - minC;
      if (delta < 0.04) continue;
      final saturation = delta / (1 - (2 * lightness - 1).abs());

      double hue;
      if (maxC == r) {
        hue = ((g - b) / delta) % 6;
      } else if (maxC == g) {
        hue = (b - r) / delta + 2;
      } else {
        hue = (r - g) / delta + 4;
      }
      hue = (hue * 60 + 360) % 360;

      final bucket = (hue / 30).floor().clamp(0, 11);
      // 明度太极端时降权：全黑封面的亮部、逆光照片的高光都不具代表性。
      final lightnessWeight =
          1.0 - ((lightness - 0.5).abs() / 0.5) * 0.6;
      final weight = saturation * saturation * lightnessWeight;
      weightPerBucket[bucket] += weight;
      rSum[bucket] += r * weight;
      gSum[bucket] += g * weight;
      bSum[bucket] += b * weight;
    }

    var bestBucket = -1;
    var bestWeight = 0.0;
    for (var i = 0; i < 12; i++) {
      if (weightPerBucket[i] > bestWeight) {
        bestWeight = weightPerBucket[i];
        bestBucket = i;
      }
    }
    if (bestBucket < 0 || bestWeight <= 0) return null;

    final w = weightPerBucket[bestBucket];
    final averaged = Color.fromARGB(
      255,
      (rSum[bestBucket] / w * 255).round().clamp(0, 255),
      (gSum[bestBucket] / w * 255).round().clamp(0, 255),
      (bSum[bestBucket] / w * 255).round().clamp(0, 255),
    );

    final hsl = HSLColor.fromColor(averaged);
    // 夹到界面可用区间：太灰认不出颜色，太亮/太暗都会让文字对比度失守。
    final accent = hsl
        .withSaturation(hsl.saturation.clamp(0.42, 0.82))
        .withLightness(hsl.lightness.clamp(0.46, 0.62))
        .toColor();
    final secondary = hsl
        .withHue((hsl.hue + 28) % 360)
        .withSaturation(hsl.saturation.clamp(0.32, 0.7))
        .withLightness(hsl.lightness.clamp(0.5, 0.68))
        .toColor();
    final background = hsl
        .withSaturation(hsl.saturation.clamp(0.18, 0.5))
        .withLightness(0.09)
        .toColor();

    return CoverPalette(
      accent: accent,
      secondary: secondary,
      background: background,
    );
  }

  @visibleForTesting
  void clearCache() {
    _cache.clear();
    _failedAt.clear();
    _cacheOrder.clear();
  }
}

class _Pixels {
  const _Pixels(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width;
  final int height;
}
