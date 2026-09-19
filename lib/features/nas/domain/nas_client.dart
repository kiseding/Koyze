import 'package:dio/dio.dart';

import '../../../core/network/app_http_client.dart';
import '../../player/domain/music_item.dart';
import 'nas_config.dart';
import 'nas_kind.dart';

class NasApiException implements Exception {
  const NasApiException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

abstract class NasClient {
  NasClient({Dio? dio})
      : _dio = dio ??
            AppHttpClient.create(
              options: BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
              ),
            ),
        _ownsDio = dio == null;

  final Dio _dio;
  final bool _ownsDio;

  Dio get dio => _dio;

  NasKind get kind;

  void dispose() {
    if (_ownsDio) _dio.close(force: true);
  }

  Future<NasPingResult> connect(NasConfig config, NasSecrets secrets);

  Future<List<NasPlaylistInfo>> getPlaylists(
    NasConfig config,
    NasSecrets secrets,
  );

  Future<List<MusicItem>> getPlaylistSongs(
    NasConfig config,
    NasSecrets secrets,
    String playlistId,
  );

  Future<List<MusicItem>> search(
    NasConfig config,
    NasSecrets secrets,
    String query, {
    int page = 1,
    int limit = 20,
  });

  String streamUrl(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music, {
    required String quality,
  });

  Future<String?> getLyrics(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music,
  );

  String describeDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查服务器地址和网络';
      case DioExceptionType.connectionError:
        final message = error.message ?? '';
        if (message.contains('CERTIFICATE_VERIFY_FAILED')) {
          return '证书校验失败。自签名证书请改用受信证书，或在局域网使用 HTTP';
        }
        return '无法连接到服务器';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        if (code == 401 || code == 403) return '用户名或密码错误';
        if (code == 404) return '服务器路径不正确';
        if (code != null && code >= 500) return '服务器内部错误';
        return 'HTTP $code';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.unknown:
        return error.message ?? '未知网络错误';
      default:
        return error.message ?? '未知网络错误';
    }
  }

  int? asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  List<Map<String, dynamic>> asList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    if (raw is Map) return [Map<String, dynamic>.from(raw)];
    return const [];
  }

  Map<String, dynamic>? asMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  int? maxBitRateForQuality(String quality) {
    return switch (quality) {
      '128k' => 128000,
      '192k' => 192000,
      '320k' => 320000,
      'flac' || 'flac24bit' || 'hires' => null,
      _ => 320000,
    };
  }

  int? maxKbpsForQuality(String quality) {
    return switch (quality) {
      '128k' => 128,
      '192k' => 192,
      '320k' => 320,
      'flac' || 'flac24bit' || 'hires' => null,
      _ => 320,
    };
  }
}

