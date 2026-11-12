// 封面字节的 Web 版加载器（仅 Web 构建存在）。
//
// 原生版封面走 `ArtworkBytesLoader._IoArtworkHttpClient` → dart:io 的
// `HttpClient()`。dart2js 下 dart:io 只有类型 stub，`HttpClient()` 一构造
// 就抛 "Unsupported operation"，而且这一句在 `load()` 的 try 之外，异常直接
// 冒到 `ArtworkNetworkImage._loadAsync` 的 catch，被静默吞掉后走 errorBuilder。
// 表现就是：列表、播放页、迷你播放条上的封面**全部**是占位图标，控制台一条
// 日志都没有。
//
// 浏览器里改走同源 `/api/stream`：服务端代发请求并注入 UA / Referer，
// 既绕开 CORS，也满足网易、QQ、酷狗 CDN 的防盗链要求。浏览器自己发的话，
// Referer 是 forbidden header 根本设不上，请求一律 403。

import 'dart:typed_data';

import 'package:dio/browser.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';

export 'web_source_import.dart' show isWebBuild;

/// 通过同源代理取回封面字节。
///
/// 超限、非 2xx、空响应都抛异常，由 `ArtworkNetworkImage._loadAsync` 统一
/// 接住并尝试 `artworkFallbackUrls` 里的备用尺寸。
Future<Uint8List> loadArtworkBytesViaBrowser(
  Uri uri, {
  required int maximumBytes,
  required Duration timeout,
  void Function(int cumulative, int? total)? onProgress,
}) async {
  final dio = Dio(
    BaseOptions(
      responseType: ResponseType.bytes,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      // 4xx/5xx 也要读 body，这里自己判状态码，避免 Dio 抛出的
      // DioException 把真实状态码埋进字符串。
      validateStatus: (_) => true,
      followRedirects: true,
    ),
  );
  // 服务端口令模式靠 HttpOnly cookie 鉴权，浏览器适配器默认不带 cookie。
  dio.httpClientAdapter = BrowserHttpClientAdapter()..withCredentials = true;
  try {
    final target = Uri.base.resolve(
      '/api/stream?url=${Uri.encodeComponent(uri.toString())}',
    );
    final response = await dio.getUri<List<int>>(
      target,
      onReceiveProgress: (received, total) {
        onProgress?.call(received, total > 0 ? total : null);
      },
    );
    final status = response.statusCode ?? 0;
    if (status != 200 && status != 206) {
      throw NetworkImageLoadException(statusCode: status, uri: uri);
    }
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw NetworkImageLoadException(statusCode: status, uri: uri);
    }
    if (data.length > maximumBytes) {
      throw Exception(
        'artwork exceeds maximumBytes: ${data.length} > $maximumBytes ($uri)',
      );
    }
    return data is Uint8List ? data : Uint8List.fromList(data);
  } finally {
    dio.close(force: true);
  }
}
