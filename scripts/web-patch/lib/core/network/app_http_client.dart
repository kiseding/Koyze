// Web 版：与原生版公开 API 完全一致，多挂一个跨域重写拦截器。
//
// 浏览器不能直连 kugou.com / music.163.com 等域名（CORS），也不能自定义
// User-Agent / Referer（防盗链需要）。内置音源的 Dio 实例几乎都从
// AppHttpClient.create 出来，这里统一把跨域请求改写到同源 /api/proxy，
// 由 Node 服务代发并注入防盗链头。原生平台文件完全不动。

import 'package:dio/browser.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../logging/app_log.dart';

final class AppHttpClient {
  static Dio create({BaseOptions? options}) {
    final client = Dio(options ?? BaseOptions());
    if (kIsWeb) {
      // 服务端口令走 HttpOnly cookie 会话；浏览器适配器默认不带 cookie，
      // 不打开这个开关，设了 KOYZE_TOKEN 之后所有 /api 请求都会 401。
      client.httpClientAdapter = BrowserHttpClientAdapter()
        ..withCredentials = true;
      client.interceptors.add(_WebProxyInterceptor());
    }
    client.interceptors.add(_DiagnosticNetworkInterceptor());
    return client;
  }

  static Dio createDownload() => create(
    options: BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 5),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (status) => status != null && status >= 200 && status < 400,
    ),
  );
}

/// 浏览器禁止脚本设置的请求头（Fetch 规范的 forbidden header name）。
///
/// 各音源为了绕防盗链会手动塞 `Origin` / `Referer` / `Connection` 这类头，
/// 但浏览器会静默丢弃它们并往控制台刷 `Refused to set unsafe header`。
/// 这里在请求发出前统一摘掉——实际发出的请求与之前完全一致（浏览器本来
/// 就不发这些头），只是不再产生成片的警告。
const Set<String> _forbiddenHeaders = {
  'accept-charset',
  'accept-encoding',
  'access-control-request-headers',
  'access-control-request-method',
  'connection',
  'content-length',
  'cookie',
  'cookie2',
  'date',
  'dnt',
  'expect',
  'host',
  'keep-alive',
  'origin',
  'referer',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'user-agent',
  'via',
};

bool _isForbiddenHeader(String key) {
  final lower = key.toLowerCase();
  return _forbiddenHeaders.contains(lower) ||
      lower.startsWith('proxy-') ||
      lower.startsWith('sec-');
}

/// 把发往第三方域名的请求改写成同源代理请求。
final class _WebProxyInterceptor extends Interceptor {
  static final Uri _base = Uri.base;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 不论同源与否，浏览器都不允许设置这些头。同源请求以前直接放行，
    // 于是 Origin 之类的头一路带到 fetch 里，控制台刷警告。
    options.headers.removeWhere((key, _) => _isForbiddenHeader(key));

    final uri = options.uri;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return handler.next(options);
    }
    final sameOrigin = uri.host == _base.host &&
        uri.port == _base.port &&
        uri.scheme == _base.scheme;
    // 只放行「同源」请求。第三方站点的路径也可能以 /api/ 开头
    // （例如 mobiles.kugou.com/api/v3/rank/list），不能按路径判断。
    if (sameOrigin) {
      return handler.next(options);
    }

    // 保留原始地址供服务端注入 UA / Referer。
    final original = uri.toString();
    final proxied = _base.resolve(
      '/api/proxy?url=${Uri.encodeComponent(original)}',
    );
    options.path = '';
    options.baseUrl = proxied.toString();
    handler.next(options);
  }
}

final class _DiagnosticNetworkInterceptor extends Interceptor {
  static const _startedAtKey = '_diagnosticRequestStartedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now();
    AppLog.instance.record(
      'network.request',
      '${options.method} ${_target(options)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final statusCode = response.statusCode;
    AppLog.instance.record(
      'network.response',
      '${response.requestOptions.method} ${_target(response.requestOptions)} '
          'status=$statusCode elapsed=${_elapsed(response.requestOptions)}ms',
      level: statusCode != null && statusCode >= 400
          ? AppLogLevel.warning
          : AppLogLevel.info,
    );
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final responseStatus = error.response?.statusCode;
    final cancelled = error.type == DioExceptionType.cancel;
    AppLog.instance.record(
      cancelled ? 'network.cancel' : 'network.error',
      '${error.requestOptions.method} ${_target(error.requestOptions)} '
          'type=${error.type.name} status=$responseStatus '
          'elapsed=${_elapsed(error.requestOptions)}ms error=${error.message}',
      level: cancelled ? AppLogLevel.info : AppLogLevel.error,
    );
    handler.next(error);
  }

  String _target(RequestOptions options) {
    final uri = options.uri;
    final port = uri.hasPort ? ':${uri.port}' : '';
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.scheme}://${uri.host}$port$path';
  }

  int _elapsed(RequestOptions options) {
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! DateTime) return -1;
    return DateTime.now().difference(startedAt).inMilliseconds;
  }
}
