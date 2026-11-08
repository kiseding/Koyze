import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/app_version.dart';
import '../../../core/network/app_http_client.dart';

/// 一个可用的更新。
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.tag,
    required this.notes,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.publishedAt,
  });

  final String version;
  final String tag;
  final String notes;
  final String? downloadUrl;
  final int sizeBytes;
  final DateTime? publishedAt;

  bool get hasAsset => downloadUrl != null && downloadUrl!.isNotEmpty;
}

/// 应用内更新。
///
/// 版本源是 GitHub Releases：CI 已经在推 tag 的时候校验 tag 与 pubspec 版本
/// 一致（`build-android.yml`），所以 `releases/latest` 的 tag 就是一份可信的
/// 版本号，不需要额外维护一个更新清单。
///
/// 只做「检查 + 下载 + 交给系统安装器」三件事：签名校验交给 Android 自己
/// （同签名的包才能覆盖安装），这里不重复实现一遍。
class UpdateService {
  UpdateService({
    Dio? dio,
    this.owner = 'kiseding',
    this.repo = 'Koyze',
    this.currentVersion = kAppVersion,
  }) : _dio =
           dio ??
           AppHttpClient.create(
             options: BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               headers: {
                 'Accept': 'application/vnd.github+json',
                 'User-Agent': 'Koyze-Updater',
               },
             ),
           );

  final Dio _dio;
  final String owner;
  final String repo;
  final String currentVersion;

  static const MethodChannel _channel = MethodChannel(
    'koyze/android_file_access',
  );

  /// 检查更新。返回 null 表示已是最新或无法判断（网络/解析失败）。
  Future<AppUpdate?> check() async {
    try {
      final response = await _dio.get<dynamic>(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
      );
      final body = response.data;
      final map = body is String ? jsonDecode(body) : body;
      if (map is! Map) return null;
      final tag = map['tag_name']?.toString() ?? '';
      final version = _normalize(tag);
      if (version.isEmpty) return null;
      if (_compare(version, currentVersion) <= 0) return null;

      String? apkUrl;
      var size = 0;
      final assets = map['assets'];
      if (assets is List) {
        for (final asset in assets.whereType<Map>()) {
          final name = asset['name']?.toString().toLowerCase() ?? '';
          if (!name.endsWith('.apk')) continue;
          apkUrl = asset['browser_download_url']?.toString();
          size = asset['size'] is num ? (asset['size'] as num).toInt() : 0;
          break;
        }
      }

      return AppUpdate(
        version: version,
        tag: tag,
        notes: map['body']?.toString() ?? '',
        downloadUrl: apkUrl,
        sizeBytes: size,
        publishedAt: DateTime.tryParse(map['published_at']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  /// 下载到 cache/update 下并返回本地路径。
  ///
  /// 目录必须与 `res/xml/updater_paths.xml` 里声明的 `cache-path` 一致，
  /// 否则 FileProvider 会拒绝把文件暴露给安装器。
  Future<String> download(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = update.downloadUrl;
    if (url == null || url.isEmpty) {
      throw StateError('这一版没有提供 APK 资源');
    }
    final cache = await getTemporaryDirectory();
    final dir = Directory('${cache.path}${Platform.pathSeparator}update');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file =
        '${dir.path}${Platform.pathSeparator}koyze-${update.version}.apk';

    await _dio.download(
      url,
      file,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      options: Options(headers: {'Accept': 'application/octet-stream'}),
    );
    return file;
  }

  /// 交给系统安装器。返回 false 表示没装起来（常见原因：未授予安装权限，
  /// 此时系统已经跳到授权页）。
  Future<bool> install(String path) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('installApk', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  static String _normalize(String tag) {
    var value = tag.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    // 只保留数字与点：tag 里可能带 -beta、+build 之类的后缀。
    final match = RegExp(r'^\d+(\.\d+)*').firstMatch(value);
    return match?.group(0) ?? '';
  }

  /// 逐段比较版本号，缺失的段按 0 处理。
  static int _compare(String a, String b) {
    final left = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final right = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  @visibleForTesting
  static int compareVersions(String a, String b) => _compare(a, b);
}
