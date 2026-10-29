import 'package:dio/dio.dart';

import '../../../core/network/app_http_client.dart';
import 'radio_station.dart';

/// Radio Browser 的公开 HTTP 客户端。
///
/// 服务由志愿者维护，官方要求按 DNS 轮询选节点、写清 User-Agent，并在
/// 命中失败时换一个镜像重试。这里把可用的三个节点写死并顺序降级——
/// DNS 轮询本身需要一次 `lookup`，对只拉一页列表的客户端反而是多余延迟。
class RadioBrowserClient {
  RadioBrowserClient({Dio? dio, List<String>? hosts})
    : _dio =
          dio ??
          AppHttpClient.create(
            options: BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {'User-Agent': 'Koyze/1.0 (Flutter)'},
            ),
          ),
      _hosts = hosts ?? defaultHosts;

  final Dio _dio;
  final List<String> _hosts;

  static const List<String> defaultHosts = [
    'https://de1.api.radio-browser.info',
    'https://nl1.api.radio-browser.info',
    'https://at1.api.radio-browser.info',
  ];

  /// 最热门（按点击量）。
  Future<List<RadioStation>> popular({int limit = 60}) {
    return _get('/json/stations/topclick/$limit');
  }

  /// 名称搜索；[query] 为空时等价于 [popular]。
  Future<List<RadioStation>> search(String query, {int limit = 60}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return popular(limit: limit);
    return _get(
      '/json/stations/search',
      query: {
        'name': trimmed,
        'limit': '$limit',
        'order': 'clickcount',
        'reverse': 'true',
        'hidebroken': 'true',
      },
    );
  }

  /// 按标签（风格）筛选。
  Future<List<RadioStation>> byTag(String tag, {int limit = 60}) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return popular(limit: limit);
    return _get(
      '/json/stations/search',
      query: {
        'tag': trimmed,
        'limit': '$limit',
        'order': 'clickcount',
        'reverse': 'true',
        'hidebroken': 'true',
      },
    );
  }

  /// 逐个节点尝试，全部失败才抛出最后一个错误。
  Future<List<RadioStation>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    Object? lastError;
    for (final host in _hosts) {
      try {
        final response = await _dio.get<List<dynamic>>(
          '$host$path',
          queryParameters: query,
        );
        final data = response.data ?? const [];
        final stations = <RadioStation>[];
        for (final entry in data) {
          if (entry is! Map) continue;
          final station = RadioStation.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (station != null) stations.add(station);
        }
        return stations;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('Radio Browser 节点均不可用');
  }
}
