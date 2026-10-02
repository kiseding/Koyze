import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/music_source/platform/kw_source.dart';
import 'package:koyze/core/music_source/platform/music_platform.dart';

void main() {
  test('service Dio clients are reused for the same headers', () {
    final source = KwSource();
    addTearDown(source.dispose);
    final first = source.createDioForService(
      headers: {'Referer': 'https://www.kuwo.cn/'},
    );
    final second = source.createDioForService(
      headers: {'Referer': 'https://www.kuwo.cn/'},
    );
    final other = source.createDioForService(
      headers: {'Referer': 'https://y.qq.com/'},
    );

    expect(identical(first, second), isTrue);
    expect(identical(first, other), isFalse);
  });

  test('search failures stay distinguishable from an empty result', () {
    final source = KwSource();
    addTearDown(source.dispose);

    final timeout = source.noteFailure('search', TimeoutException('slow'));
    expect(timeout.kind, SourceFailureKind.timeout);
    expect(timeout.toString(), '音源响应超时');

    final offline = source.noteFailure(
      'search',
      DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError,
        error: const SocketException('offline'),
      ),
    );
    expect(offline.kind, SourceFailureKind.offline);
    expect(offline.toString(), '网络不可用，请检查连接后再试');

    final http = SourceFailure.classify(
      'tx',
      'search',
      DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 502,
        ),
      ),
    );
    expect(http.kind, SourceFailureKind.http);
    expect(http.toString(), '音源接口返回错误（502）');
  });
}
