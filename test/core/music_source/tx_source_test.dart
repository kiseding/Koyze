import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/music_source/platform/tx_source.dart';

class _SmartboxAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      '{"code":0,"data":{"order":["song"],"song":{"itemlist":'
      '[{"name":"晴天","mid":"song-mid"}]}}}',
      200,
      headers: {Headers.contentTypeHeader: ['application/json; charset=utf-8']},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('QQ suggestions use smartbox and parse actual candidate data', () async {
    final adapter = _SmartboxAdapter();
    final source = TxSource(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(source.dispose);

    final suggestions = await source.searchSuggestions('晴');

    expect(adapter.request?.uri.host, 'c.y.qq.com');
    expect(adapter.request?.uri.path, '/splcloud/fcgi-bin/smartbox_new.fcg');
    expect(adapter.request?.queryParameters['key'], '晴');
    expect(adapter.request?.queryParameters['is_xml'], '0');
    expect(suggestions, [const SearchSuggestion(text: '晴天', type: 'song')]);
  });
}
