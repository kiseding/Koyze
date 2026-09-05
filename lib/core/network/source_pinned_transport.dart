import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'source_request_policy.dart';

typedef SourceDioFactory = Dio Function();
typedef SourceDioExecutor =
    Future<Response<dynamic>> Function(
      Dio dio,
      ValidatedSourceRequest request,
      CancelToken cancelToken,
    );
typedef SourceSocketStarter =
    Future<ConnectionTask<Socket>> Function(
      InternetAddress address,
      int port, {
      required String host,
      required bool useTls,
    });
typedef SourceDioCloser = void Function(Dio dio);

class SourcePinnedTransport {
  final SourceDioFactory createDio;
  final SourceDioExecutor execute;
  final SourceDioCloser closeDio;

  /// 是否走原生 HttpClient 执行（默认 true）。
  /// dio 的 IOHttpClientAdapter 与自定义 connectionFactory 组合在部分
  /// 音源 API 上会挂起或返回 400（见聆澜源故障），原生直连稳定。
  final bool useNativeExecutor;

  SourcePinnedTransport({
    SourceDioFactory? createDio,
    SourceDioExecutor? execute,
    SourceDioCloser? closeDio,
    this.useNativeExecutor = true,
  }) : createDio = createDio ?? Dio.new,
       execute = execute ?? _execute,
       closeDio = closeDio ?? ((dio) => dio.close(force: true));

  Future<SourceTransportResponse> call(
    ValidatedSourceRequest request,
    SourceRequestCancellation cancellation,
  ) async {
    if (cancellation.isCancelled) _throwCancelled();
    if (useNativeExecutor && _supportsNativeBody(request.body)) {
      return _callNative(request, cancellation);
    }
    final dio = createDio();
    final cancelToken = CancelToken();
    var closed = false;

    void close() {
      if (closed) return;
      closed = true;
      closeDio(dio);
    }

    unawaited(
      cancellation.future.then((reason) {
        cancelToken.cancel(reason);
        close();
      }),
    );
    if (cancellation.isCancelled) {
      close();
      _throwCancelled();
    }

    dio.httpClientAdapter = IOHttpClientAdapter(
      // 关闭 dio 自动 gzip：第三方音源 API 对带 gzip 编码头的请求
      // 返回 403/400（如聆澜源），关闭后与 curl 直连行为一致。
      createHttpClient: () {
        final client = HttpClient()..autoUncompress = false;
        client.connectionFactory = connectionFactory(request);
        return client;
      },
    );
    try {
      final response = await Future.any([
        execute(dio, request, cancelToken),
        cancellation.future.then<Response<dynamic>>(
          (reason) => throw SourceRequestPolicyException('cancelled', reason),
        ),
      ]);
      if (cancellation.isCancelled) {
        close();
        _throwCancelled();
      }
      final responseBody = response.data as ResponseBody;
      final body = (() async* {
        try {
          await for (final chunk in responseBody.stream) {
            yield chunk;
          }
        } finally {
          close();
        }
      })();
      final responseHeaders = <String, List<String>>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = List.unmodifiable(values);
      });
      return SourceTransportResponse(
        statusCode: response.statusCode,
        statusMessage: response.statusMessage ?? '',
        headers: responseHeaders,
        body: body,
        close: close,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }

  /// 原生 HttpClient 执行：pinned 直连 + failover + 流式响应 + 取消。
  /// 避免 dio IOHttpClientAdapter 与自定义 connectionFactory 的兼容问题
  /// （部分音源 API 挂起或返回 400/403）。
  Future<SourceTransportResponse> _callNative(
    ValidatedSourceRequest request,
    SourceRequestCancellation cancellation,
  ) async {
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = request.timeout;
    client.connectionFactory = connectionFactory(request);
    var closed = false;

    void close() {
      if (closed) return;
      closed = true;
      client.close(force: true);
    }

    unawaited(cancellation.future.then((_) => close()));

    try {
      final httpRequest = await client
          .openUrl(request.method, request.uri)
          .timeout(request.timeout);
      request.headers.forEach((name, value) {
        httpRequest.headers.set(name, value);
      });
      // 与 curl 直连一致：显式禁用 gzip，部分音源 API 对 gzip 头拒答。
      httpRequest.headers.set('Accept-Encoding', 'identity');
      final requestBody = request.body;
      if (requestBody is String) {
        httpRequest.add(utf8.encode(requestBody));
      } else if (requestBody is List<int>) {
        httpRequest.add(requestBody);
      }
      final response = await httpRequest.close().timeout(request.timeout);
      final headers = <String, List<String>>{};
      response.headers.forEach((name, values) {
        headers[name] = List.unmodifiable(values);
      });
      final responseBody = (() async* {
        try {
          await for (final chunk in response) {
            yield chunk;
          }
        } finally {
          close();
        }
      })();
      return SourceTransportResponse(
        statusCode: response.statusCode,
        statusMessage: response.reasonPhrase,
        headers: headers,
        body: responseBody,
        close: close,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }

  /// HttpClient accepts bytes, while Dio also supports structured one-shot
  /// payloads such as FormData and streams. Keep those on the pinned Dio path
  /// instead of guessing an encoding or consuming a non-replayable body.
  static bool _supportsNativeBody(dynamic body) =>
      body == null || body is String || body is List<int>;

  static Future<ConnectionTask<Socket>> Function(Uri, String?, int?)
  connectionFactory(
    ValidatedSourceRequest request, [
    SourceSocketStarter? startSocket,
  ]) {
    var nextAddress = 0;
    final starter = startSocket ?? startPinnedSocket;
    return (uri, proxyHost, proxyPort) {
      // 按需求放开代理：不再拦截 proxy，改为直连已校验的目标地址。
      // 轮转起始 IP，但连接层负责 failover 到列表里的其它 IP。
      final start = nextAddress % request.addresses.length;
      nextAddress++;
      final rotated = <InternetAddress>[
        for (var i = 0; i < request.addresses.length; i++)
          request.addresses[(start + i) % request.addresses.length],
      ];
      return starterWithFailover(
        rotated,
        uri.port,
        host: uri.host,
        useTls: uri.scheme.toLowerCase() == 'https',
        connect: starter,
      );
    };
  }

  /// 连接单个 IP，TLS 用原 hostname（SNI + 证书校验匹配）。
  static Future<ConnectionTask<Socket>> startPinnedSocket(
    InternetAddress address,
    int port, {
    required String host,
    required bool useTls,
  }) async {
    final rawTask = await Socket.startConnect(address, port);
    if (!useTls) return rawTask;
    final secureFuture = rawTask.socket.then(
      (socket) => SecureSocket.secure(socket, host: host),
    );
    return ConnectionTask.fromSocket(secureFuture, rawTask.cancel);
  }

  /// 依次尝试候选 IP，首个真正建立连接（含 TLS）的即返回。
  /// 修复：DNS 解析常返回多个 IP（如 onrender 的两个 Cloudflare 地址），
  /// 其中个别 IP 的 TCP 通但 TLS/HTTP 挂起。盲目轮流 pin 会导致
  /// “第一首能播、后续解析卡死”。这里对每个 IP 等连接+TLS 完成，
  /// 超时或失败立即 cancel 并换下一个。
  static const _connectFailoverTimeout = Duration(seconds: 5);

  static Future<ConnectionTask<Socket>> starterWithFailover(
    List<InternetAddress> addresses,
    int port, {
    required String host,
    required bool useTls,
    SourceSocketStarter? connect,
  }) async {
    final connectFn = connect ?? startPinnedSocket;
    Object? lastError;
    for (final address in addresses) {
      ConnectionTask<Socket>? task;
      try {
        // connectFn 是 async：await 它拿到 ConnectionTask 时 TCP 已建立，
        // 但 TLS（SecureSocket.secure）仍在 task.socket 里推进。
        // 必须在这里等 task.socket，才能确认 TLS 握手真正完成；
        // 否则对“TCP通但TLS挂起”的 IP 会误判为成功。
        task = await connectFn(address, port, host: host, useTls: useTls);
        // 等连接（含 TLS）真正建立，确认该 IP 可用后再交给 Dio 使用。
        await task.socket.timeout(_connectFailoverTimeout);
        return task;
      } catch (e) {
        lastError = e;
        try {
          task?.cancel();
        } catch (_) {}
      }
    }
    if (lastError != null) throw lastError;
    throw const SocketException('No addresses to connect to');
  }

  static Future<Response<dynamic>> _execute(
    Dio dio,
    ValidatedSourceRequest request,
    CancelToken cancelToken,
  ) {
    final headers = Map<String, dynamic>.from(request.headers);
    // 部分第三方音源 API（聆澜等）对带 gzip 编码头的请求返回 403/400，
    // 显式声明 identity 编码，与 curl 直连一致。
    headers.putIfAbsent('Accept-Encoding', () => 'identity');
    return dio.request<dynamic>(
      request.uri.toString(),
      data: request.body,
      options: Options(
        method: request.method,
        headers: headers,
        responseType: ResponseType.stream,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (_) => true,
        sendTimeout: request.timeout,
        receiveTimeout: request.timeout,
      ),
      cancelToken: cancelToken,
    );
  }

  Never _throwCancelled() => throw const SourceRequestPolicyException(
    'cancelled',
    'Source request was cancelled',
  );
}
