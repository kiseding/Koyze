import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../network/artwork_auth_registry.dart';
import '../network/artwork_load_gate.dart';
import '../network/outbound_url.dart';
import 'artwork_disk_cache.dart';
import 'route_entrance_gate.dart';

/// Headers / client identity required by some music CDNs (especially NetEase).
///
/// Critical: [NetworkImage] uses `HttpHeaders.add`, so a custom User-Agent is
/// **appended** to the default `Dart/x.x (dart:io)` UA. NetEase CDN then still
/// sees the Dart UA and returns 403 HTML. We must set [HttpClient.userAgent]
/// (or `headers.set`) so only one browser UA is sent.
const String kArtworkUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

Map<String, String> artworkRequestHeaders(String url) {
  // 自己搭的 WebDAV 封面要带 Authorization，按 origin 取登记过的头。
  final registered = artworkAuthFor(url);
  if (registered != null) {
    return {
      ...registered,
      'User-Agent': registered['User-Agent'] ?? kArtworkUserAgent,
    };
  }
  final lower = url.toLowerCase();
  if (lower.contains('music.126.net') ||
      lower.contains('126.net') ||
      lower.contains('music.163.com')) {
    // 网易云：防盗链，需要浏览器 UA + 网易 Referer
    return const {
      'User-Agent': kArtworkUserAgent,
      'Referer': 'https://music.163.com/',
    };
  }
  if (lower.contains('y.gtimg.cn') ||
      lower.contains('y.ggtimg.cn') ||
      lower.contains('imgcache.qq.com')) {
    // 腾讯系封面：防盗链，需 QQ 音乐 Referer
    return const {
      'User-Agent': kArtworkUserAgent,
      'Referer': 'https://y.qq.com/',
    };
  }
  if (lower.contains('img1.kuwo.cn') || lower.contains('kuwo.cn')) {
    // 酷我封面：防盗链
    return const {
      'User-Agent': kArtworkUserAgent,
      'Referer': 'https://www.kuwo.cn/',
    };
  }
  if (lower.contains('kugou.com') || lower.contains('kgimg.com')) {
    // 酷狗封面：防盗链
    return const {
      'User-Agent': kArtworkUserAgent,
      'Referer': 'https://www.kugou.com/',
    };
  }
  return const {};
}

bool artworkNeedsBrowserClient(String url) {
  return artworkRequestHeaders(url).isNotEmpty;
}

/// Extra CDN renditions to try when [url] 404s or returns a tiny HTML error.
///
/// QQ album art often advertises `T002R1000x1000…jpg` but only the 500px
/// file exists. Scraped NAS / Subsonic songs keep `platform=subsonic`, so
/// platform-based artwork candidates never run for them.
List<String> artworkFallbackUrls(String url) {
  if (url.isEmpty) return const [];
  final fallbacks = <String>[];
  void add(String value) {
    if (value.isNotEmpty && value != url && !fallbacks.contains(value)) {
      fallbacks.add(value);
    }
  }

  if (url.contains('R1000x1000') || url.contains('R800x800')) {
    add(
      url
          .replaceAll('R1000x1000', 'R500x500')
          .replaceAll('R800x800', 'R500x500'),
    );
  }

  final lower = url.toLowerCase();
  if (lower.contains('126.net') || lower.contains('music.163.com')) {
    final bare = url.split('?').first;
    add('$bare?param=500y500');
    add(bare);
  }
  if (lower.contains('kuwo.cn') && url.contains('/500/')) {
    add(url.replaceFirst('/500/', '/300/'));
    add(url.replaceFirst('/500/', '/120/'));
  }
  if (lower.contains('imge.kugou.com')) {
    add(
      url.replaceFirstMapped(
        RegExp(r'(imge\.kugou\.com/[^/]+/)\d+/'),
        (match) => '${match[1]}480/',
      ),
    );
    add(
      url.replaceFirstMapped(
        RegExp(r'(imge\.kugou\.com/[^/]+/)\d+/'),
        (match) => '${match[1]}240/',
      ),
    );
  }
  return fallbacks;
}

class ArtworkLimitException implements Exception {
  ArtworkLimitException(this.message);
  final String message;

  @override
  String toString() => 'ArtworkLimitException: $message';
}

/// Minimal HTTP client surface used by [ArtworkBytesLoader].
abstract interface class ArtworkHttpClient {
  Future<HttpClientRequest> getUrl(Uri url);
  void close({bool force = false});
  set userAgent(String? value);
}

typedef ArtworkClientFactory = ArtworkHttpClient Function();

class _IoArtworkHttpClient implements ArtworkHttpClient {
  _IoArtworkHttpClient() : _client = HttpClient();

  final HttpClient _client;

  @override
  set userAgent(String? value) {
    _client.userAgent = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _client.getUrl(url);

  @override
  void close({bool force = false}) => _client.close(force: force);
}

/// Bounded download of artwork bytes with forced client close.
class ArtworkBytesLoader {
  ArtworkBytesLoader({
    ArtworkClientFactory? createClient,
    this.maximumBytes = 8 * 1024 * 1024,
    this.timeout = const Duration(seconds: 12),
  }) : createClient = createClient ?? _IoArtworkHttpClient.new;

  final ArtworkClientFactory createClient;
  final int maximumBytes;
  final Duration timeout;

  Future<Uint8List> load(
    Uri uri,
    Map<String, String> headers,
    void Function(int, int?) onProgress,
  ) async {
    final client = createClient();
    try {
      return await _loadWithClient(
        client,
        uri,
        headers,
        onProgress,
      ).timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _loadWithClient(
    ArtworkHttpClient client,
    Uri uri,
    Map<String, String> headers,
    void Function(int, int?) onProgress,
  ) async {
    final userAgent = _headerValue(headers, 'user-agent');
    if (userAgent != null) {
      client.userAgent = userAgent;
    }

    final request = await client.getUrl(uri);
    headers.forEach((name, value) {
      if (name.toLowerCase() == 'user-agent') return;
      request.headers.set(name, value);
    });

    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: uri,
      );
    }

    final declared = response.contentLength;
    if (declared > maximumBytes) {
      await response.drain<void>();
      throw ArtworkLimitException(
        'Content-Length $declared exceeds maximumBytes $maximumBytes',
      );
    }

    final builder = BytesBuilder(copy: false);
    var cumulative = 0;
    final expected = declared >= 0 ? declared : null;

    await for (final chunk in response) {
      cumulative += chunk.length;
      if (cumulative > maximumBytes) {
        throw ArtworkLimitException(
          'Streamed body $cumulative exceeds maximumBytes $maximumBytes',
        );
      }
      builder.add(chunk);
      onProgress(cumulative, expected);
    }

    return builder.takeBytes();
  }

  static String? _headerValue(Map<String, String> headers, String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) return entry.value;
    }
    return null;
  }
}

/// 全屏播放器（正文封面与飞行封面）共用的解码宽度。
///
/// 两处必须一致，否则交接时会换一张更糊或更锐的图；预热也必须用同一档位，
/// 否则预热的是另一个缓存条目，打开播放器时封面仍要重新解码，头几帧空白
/// 看起来就是"闪一下"。
const int kPlayerArtworkDecodeWidth = 1080;

/// Physical pixels to decode a cover at. Explicit [cacheWidth] wins.
/// Otherwise the layout width is scaled by the device pixel ratio and capped
/// so a 1000×1000 CDN image is not decoded at full size for a list tile.
int artworkCachePixels({
  required int? cacheWidth,
  required double? width,
  required double maxConstraintWidth,
  required double devicePixelRatio,
}) {
  if (cacheWidth != null && cacheWidth > 0) return cacheWidth;
  final logical = width != null && width.isFinite && width > 0
      ? width
      : (maxConstraintWidth.isFinite && maxConstraintWidth > 0
            ? maxConstraintWidth
            : 320.0);
  final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final pixels = (logical * ratio).round();
  if (pixels < 1) return 1;
  if (pixels > 1080) return 1080;
  return pixels;
}

class ArtworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, int?, bool)? frameBuilder;

  /// 入场动效期间先显示占位封面，动效播完再开始下载 / 解码。
  ///
  /// 打开一页歌单时首屏十几行会同时开图：十几条连接、十几次解码全压进
  /// 动效那几帧，动效就顿在开头。文字、行高亮照常立刻显示，只把封面押后，
  /// 代价是封面晚一拍出现。
  ///
  /// 播放器封面要关掉：它本身就是展开动效的主角，而且是预热过的，
  /// 押后只会让转场中间空一块。
  final bool deferDuringEntrance;

  /// 占位封面；不给就画一块中性底色 + 音符。
  final Widget? placeholder;

  const ArtworkImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.errorBuilder,
    this.frameBuilder,
    this.deferDuringEntrance = true,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pixels = artworkCachePixels(
          cacheWidth: cacheWidth,
          width: width,
          maxConstraintWidth: constraints.maxWidth,
          devicePixelRatio: MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1,
        );
        final provider = ResizeImage.resizeIfNeeded(
          pixels,
          null,
          ArtworkNetworkImage(url),
        );
        final image = Image(
          image: provider,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: errorBuilder,
          frameBuilder: frameBuilder,
        );
        if (!deferDuringEntrance) return image;
        return RouteEntranceGate(
          builder: (context, settled) {
            // 已经解过的（同一首重新打开、播放器预热过的大图）照常立刻画，
            // 只有真的要去下载的才押后。
            if (settled || artworkIsCached(provider)) return image;
            return SizedBox(
              width: width,
              height: height,
              child:
                  placeholder ??
                  _ArtworkPlaceholder(extent: constraints.maxWidth),
            );
          },
        );
      },
    );
  }
}

/// 这张封面是否已经在 [ImageCache] 里（含正在解码的上一帧）。
///
/// 只用来决定「入场期间要不要等一等」，判断不出来就按没缓存处理——
/// 多等一帧不会出错，少等会白跑一次下载。
bool artworkIsCached(ImageProvider provider) {
  Object? key;
  // 我们的 provider 和外面包的 ResizeImage 都用 SynchronousFuture，
  // 下面的 then 会同步回调；万一真返回了异步 Future，key 仍是 null，
  // 按未缓存处理。
  unawaited(
    provider.obtainKey(ImageConfiguration.empty).then((value) => key = value),
  );
  return key != null && PaintingBinding.instance.imageCache.containsKey(key!);
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.extent});

  final double extent;

  @override
  Widget build(BuildContext context) {
    final tint = Theme.of(context).colorScheme.onSurface;
    final side = extent.isFinite && extent > 0
        ? (extent * 0.42).clamp(12.0, 40.0)
        : 18.0;
    return ColoredBox(
      color: tint.withValues(alpha: 0.06),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: side,
          color: tint.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

@immutable
class ArtworkNetworkImage extends ImageProvider<ArtworkNetworkImage> {
  const ArtworkNetworkImage(this.url, {this.scale = 1.0, this.loader});

  final String url;
  final double scale;
  final ArtworkBytesLoader? loader;

  String get resolvedUrl => normalizeOutboundUrl(url);

  ArtworkBytesLoader get _loader => loader ?? ArtworkBytesLoader();

  @override
  Future<ArtworkNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<ArtworkNetworkImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    ArtworkNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<ArtworkNetworkImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    ArtworkNetworkImage key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    try {
      assert(key == this);
      final uri = Uri.parse(key.resolvedUrl);
      // 本地文件封面（本地音乐内嵌封面缓存）：直接读文件，不走网络/磁盘缓存。
      if (uri.scheme == 'file') {
        final file = File(uri.toFilePath());
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw Exception('ArtworkNetworkImage empty local file: $uri');
        }
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return await decode(buffer);
      }
      // Prefer 12h disk cache (shared with lock-screen art download).
      Uint8List? bytes = await ArtworkDiskCache.instance.bytesForUrl(
        key.resolvedUrl,
      );
      Object? lastError;
      if (bytes == null) {
        final candidates = <String>{
          key.resolvedUrl,
          ...artworkFallbackUrls(key.resolvedUrl),
        };
        for (final candidate in candidates) {
          try {
            final candidateUri = Uri.parse(candidate);
            // 首屏十几行同时开图时排个队，别让十几条连接一起压在同一帧上。
            // 显式给类型参数：否则 T 会从 `bytes`（可空）反推成可空，
            // 下面的空判断之后就拿不回非空了。
            bytes = await artworkLoadGate.run<Uint8List>(
              () => key._loader.load(
                candidateUri,
                artworkRequestHeaders(candidate),
                (cumulative, total) {
                  chunkEvents.add(
                    ImageChunkEvent(
                      cumulativeBytesLoaded: cumulative,
                      expectedTotalBytes: total,
                    ),
                  );
                },
              ),
            );
            if (_isUsableArtwork(bytes)) {
              unawaited(ArtworkDiskCache.instance.put(key.resolvedUrl, bytes));
              lastError = null;
              break;
            }
            lastError = Exception(
              'ArtworkNetworkImage got HTML instead of image: $candidateUri',
            );
            bytes = null;
          } catch (error) {
            lastError = error;
            bytes = null;
          }
        }
      }
      if (bytes == null || bytes.lengthInBytes == 0) {
        throw lastError ??
            Exception('ArtworkNetworkImage is an empty file: $uri');
      }

      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } catch (e) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      await chunkEvents.close();
    }
  }

  static bool _isUsableArtwork(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    // NetEase sometimes returns tiny HTML error pages with 200; reject them.
    if (bytes.lengthInBytes < 200 && bytes[0] == 0x3C /* < */ ) return false;
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is ArtworkNetworkImage &&
        other.url == url &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'ArtworkNetworkImage')}("$url", scale: ${scale.toStringAsFixed(1)})';
}
