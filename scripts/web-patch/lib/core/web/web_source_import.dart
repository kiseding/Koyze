// 链接导入的 Web 版取脚本实现（仅 Web 构建存在）。
//
// 原生版走 `_importSandbox` → `IOSSourceTransport` → dart:io 的 HttpClient
// （还带 DNS pinning），浏览器里这套全部不可用：`HttpClient()` 会直接抛
// Unsupported operation，所以「从链接导入」在 Web 上永远失败。
//
// 服务端的 /api/proxy 已经做了同一件事：代发请求、注入 UA/Referer、
// 校验目标地址（禁私网）。这里只是把结果当文本取回来。

import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// Web 构建标志。这个文件只存在于 Web 构建副本里，因此恒为 true；
/// 调用处的 `else` 分支会被 dart2js 当作死代码裁掉。
const bool isWebBuild = true;

Future<String?> fetchSourceScriptViaServer(Uri uri) async {
  final dio = _sessionDio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
    ),
  );
  try {
    final target = Uri.base.resolve(
      '/api/proxy?url=${Uri.encodeComponent(uri.toString())}',
    );
    final response = await dio.getUri<String>(target);
    final text = response.data;
    if (text == null || text.isEmpty) return null;
    return text;
  } catch (_) {
    return null;
  } finally {
    dio.close(force: true);
  }
}

/// 媒体探测结果（Range 请求读回文件头）。
class WebProbeResponse {
  const WebProbeResponse({
    required this.bytes,
    required this.headers,
    this.error,
    this.timedOut = false,
  });

  final List<int> bytes;
  final Map<String, String> headers;
  final String? error;
  final bool timedOut;
}

/// 用 Range 请求读回音频文件头。
///
/// 原生版走 `SourceMediaTransport`（dart:io 的 pinned HttpClient），浏览器里
/// 这条路完全不可用，音源检测会一律判失败。这里直接用 Dio 打同源的
/// `/api/stream`：Range 由服务端转发，防盗链头也由服务端注入。
Future<WebProbeResponse> probeMediaViaServer(
  String url, {
  required int maxBytes,
  required Duration timeout,
}) async {
  final dio = _sessionDio(
    BaseOptions(
      responseType: ResponseType.bytes,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      validateStatus: (_) => true,
    ),
  );
  try {
    final target = Uri.base.resolve(url);
    final response = await dio.getUri<List<int>>(
      target,
      options: Options(
        headers: {
          // 浏览器把 Accept-Encoding 列为 forbidden header，设了会被
          // 直接丢掉并在控制台刷警告，所以这里只发 Range。
          'Range': 'bytes=0-${maxBytes - 1}',
        },
      ),
    );
    final headers = <String, String>{};
    response.headers.forEach((key, value) {
      headers[key.toLowerCase()] = value.join(',');
    });
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      return WebProbeResponse(
        bytes: const <int>[],
        headers: headers,
        error: 'HTTP $status',
      );
    }
    final data = response.data ?? const <int>[];
    return WebProbeResponse(
      bytes: data.length > maxBytes ? data.sublist(0, maxBytes) : data,
      headers: headers,
    );
  } catch (error) {
    final timedOut = error is DioException &&
        (error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.sendTimeout);
    return WebProbeResponse(
      bytes: const <int>[],
      headers: const <String, String>{},
      error: timedOut ? '探测超时' : error.toString(),
      timedOut: timedOut,
    );
  } finally {
    dio.close(force: true);
  }
}

/// 读出这个播放地址的**总字节数**（用 `Range: bytes=0-0` 拿 content-range）。
///
/// 用途：酷我等平台对未登录/无版权用户只下发 30 秒试听片段，但依然返回
/// 一个合法 URL，`validateStream` 的「有没有字节」判断会放行。要靠总字节数
/// 反推时长才能识别出这是片段。
///
/// 返回 null 表示上游没给出可信长度（chunked、无 content-range 等），
/// 此时调用方应当按「无法判断」处理，不要误杀。
Future<int?> probeMediaTotalBytes(
  String url, {
  required Duration timeout,
}) async {
  final dio = _sessionDio(
    BaseOptions(
      responseType: ResponseType.bytes,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      validateStatus: (_) => true,
      followRedirects: true,
    ),
  );
  try {
    final target = Uri.base.resolve(url);
    final response = await dio.getUri<List<int>>(
      target,
      options: Options(
        headers: {'Range': 'bytes=0-0'},
      ),
    );
    final status = response.statusCode ?? 0;
    if (status >= 400) return null;

    final headers = <String, String>{};
    response.headers.forEach((key, value) {
      headers[key.toLowerCase()] = value.join(',');
    });

    // 206 时 content-range 形如 `bytes 0-0/5276456`，斜杠后面是总长度。
    final range = headers['content-range'];
    if (range != null) {
      final slash = range.lastIndexOf('/');
      if (slash >= 0) {
        final total = int.tryParse(range.substring(slash + 1).trim());
        if (total != null && total > 0) return total;
      }
    }
    // 200 表示服务端忽略了 Range，直接给了全长。
    final length = int.tryParse(headers['content-length'] ?? '');
    if (status == 200 && length != null && length > 0) return length;
    return null;
  } catch (_) {
    return null;
  } finally {
    dio.close(force: true);
  }
}

/// 带上会话 cookie 的 Dio。服务端口令模式下 /api 靠 HttpOnly cookie 鉴权，
/// 浏览器适配器默认不带 cookie，所以这里统一打开。
Dio _sessionDio(BaseOptions options) {
  final dio = Dio(options);
  dio.httpClientAdapter = BrowserHttpClientAdapter()..withCredentials = true;
  return dio;
}
