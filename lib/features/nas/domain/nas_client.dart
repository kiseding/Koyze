import 'package:dio/dio.dart';

import '../../../core/network/app_http_client.dart';
import '../../player/domain/music_item.dart';
import 'nas_config.dart';
import 'nas_kind.dart';

/// 一次拉取的上限。以前是 500，超过的库会被静默截断；现在默认拉全量，
/// 这个值只作为防止异常服务器拖死客户端的保险丝。
const kNasLibraryLimit = 20000;

/// 串流码率：`original` 表示不转码，直接给服务器上的原文件。
const kNasQualityOriginal = 'original';

/// 可以选的档位。数字只是 kbps 上限，具体转成什么由服务器决定。
const kNasQualityOptions = <String>[
  kNasQualityOriginal,
  '320k',
  '192k',
  '128k',
];

/// `quality` 是应用统一的音质档位（hires / flac24bit / flac / 320k / 192k / 128k）。
/// NAS 侧只关心一件事：要不要压码率。无损档位放原文件，其余按 kbps 上限转码。
int? nasBitrateCapKbps(String quality) {
  return switch (quality) {
    '320k' => 320,
    '192k' => 192,
    '128k' => 128,
    _ => null,
  };
}

class NasApiException implements Exception {
  const NasApiException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

abstract class NasClient {
  NasClient({Dio? dio})
    : _dio =
          dio ??
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

  Future<List<MusicItem>> getLibrarySongs(
    NasConfig config,
    NasSecrets secrets, {
    int limit = kNasLibraryLimit,
  });

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

  /// Detailed playback contract for endpoints that need runtime headers.
  ///
  /// Existing clients keep their URL-only implementation. WebDAV overrides
  /// this method to return Basic/Bearer headers without putting credentials in
  /// MusicItem, cache metadata, or the URL.
  Future<NasPlayUrlResult> streamResult(
    NasConfig config,
    NasSecrets secrets,
    MusicItem music, {
    required String quality,
  }) async {
    return NasPlayUrlResult(
      url: streamUrl(config, secrets, music, quality: quality),
    );
  }

  /// 封面图请求头。默认空——把凭证放在 URL 里的协议（Emby 的 api_key、
  /// Plex 的 X-Plex-Token）不需要额外头；WebDAV 走 Authorization，必须覆盖。
  Map<String, String> artworkHeaders(NasConfig config, NasSecrets secrets) =>
      const {};

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
}
