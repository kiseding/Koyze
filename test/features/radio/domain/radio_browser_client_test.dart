import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/radio/domain/radio_browser_client.dart';

/// 只认识预设路由的假适配器：让客户端逻辑（降级、解析、字段兜底）
/// 可以完全离线地被测到。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responses);

  /// host → (statusCode, body)
  final Map<String, (int, String)> responses;
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.uri.host}${options.uri.path}?${options.uri.query}');
    final entry = responses[options.uri.host];
    if (entry == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'host down',
      );
    }
    return ResponseBody.fromString(
      entry.$2,
      entry.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _stationJson(String id, String name, {String tag = 'jazz'}) =>
    jsonEncode([
      {
        'stationuuid': id,
        'name': name,
        'url': 'http://example.com/$id',
        'url_resolved': 'https://example.com/$id.mp3',
        'tags': tag,
        'country': 'CN',
        'codec': 'MP3',
        'bitrate': 128,
      },
      // 无法播放的条目应该在解析阶段就被丢掉。
      {'stationuuid': 'broken', 'name': 'Broken'},
    ]);

void main() {
  group('RadioBrowserClient', () {
    test('parses a station list and drops unplayable entries', () async {
      final adapter = _FakeAdapter({
        'de1.api.radio-browser.info': (200, _stationJson('a', 'Radio A')),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final client = RadioBrowserClient(dio: dio);

      final stations = await client.popular(limit: 5);

      expect(stations, hasLength(1));
      expect(stations.first.name, 'Radio A');
      expect(stations.first.streamUrl, 'https://example.com/a.mp3');
      expect(adapter.requests.first, contains('/json/stations/topclick/5'));
    });

    test('falls back to the next mirror when a host is down', () async {
      final adapter = _FakeAdapter({
        'nl1.api.radio-browser.info': (200, _stationJson('b', 'Radio B')),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final client = RadioBrowserClient(dio: dio);

      final stations = await client.popular();

      expect(stations.single.id, 'b');
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last, contains('nl1.api.radio-browser.info'));
    });

    test('throws only after every mirror failed', () async {
      final adapter = _FakeAdapter({});
      final dio = Dio()..httpClientAdapter = adapter;
      final client = RadioBrowserClient(dio: dio);

      await expectLater(client.popular(), throwsA(isA<DioException>()));
      expect(
        adapter.requests,
        hasLength(RadioBrowserClient.defaultHosts.length),
      );
    });

    test('search sends the query and ordering parameters', () async {
      final adapter = _FakeAdapter({
        'de1.api.radio-browser.info': (200, _stationJson('c', 'Jazz FM')),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final client = RadioBrowserClient(dio: dio);

      await client.search('  jazz fm  ');

      final request = adapter.requests.single;
      expect(request, contains('/json/stations/search'));
      expect(request, contains('name=jazz'));
      expect(request, contains('order=clickcount'));
      expect(request, contains('hidebroken=true'));
    });

    test('an empty query falls back to the popular list', () async {
      final adapter = _FakeAdapter({
        'de1.api.radio-browser.info': (200, _stationJson('d', 'Top')),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final client = RadioBrowserClient(dio: dio);

      await client.search('   ');

      expect(adapter.requests.single, contains('/topclick/'));
    });

    test('byTag filters on the tag parameter', () async {
      final adapter = _FakeAdapter({
        'de1.api.radio-browser.info': (200, _stationJson('e', 'Rock')),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final client = RadioBrowserClient(dio: dio);

      await client.byTag('rock');

      expect(adapter.requests.single, contains('tag=rock'));
    });

    test('treats a null body as an empty list', () async {
      final adapter = _FakeAdapter({
        'de1.api.radio-browser.info': (200, 'null'),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final client = RadioBrowserClient(dio: dio);

      expect(await client.popular(), isEmpty);
    });
  });
}
