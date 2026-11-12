// Web 版音源引擎：公开 API 与原生版完全一致，但不加载 QuickJS。
//
// 浏览器里没有 dart:ffi，音源脚本改由同容器的 Node 服务执行（webapp/server）。
// 所有请求都走同源相对路径 /api/*，因此无论用 localhost、局域网 IP 还是
// 域名访问，都无需配置后端地址，也不会遇到 CORS。
// 其余 316 个 Dart 文件（含全部 UI）无需任何改动。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/browser.dart';
import 'package:dio/dio.dart';
import 'package:koyze/core/logging/app_log.dart';
import 'package:koyze/core/network/source_request_policy.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/custom_source/domain/lx_source_capabilities.dart';
import 'package:koyze/features/player/domain/music_item.dart';

const String customSourceExecutionUnavailableReason =
    'Custom source execution was rejected by the synchronous safety preflight.';

// 脚本在服务端执行，不再受客户端同步预检限制。
bool get isCustomSourceExecutionSupported => true;

List<String> ensureMusicInfoTypes(Map<String, dynamic> meta, String type) {
  const official = ['hires', 'flac24bit', 'flac', '320k', '128k'];
  final raw = meta['types'] ?? meta['qualitys'] ?? meta['quality'];
  final out = <String>[];
  if (raw is List) {
    for (final e in raw) {
      final s = e.toString().trim().toLowerCase();
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
  } else if (raw is Map) {
    for (final k in raw.keys) {
      final s = k.toString().trim().toLowerCase();
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
  }
  final req = type.trim().toLowerCase();
  if (req.isNotEmpty && !out.contains(req)) out.insert(0, req);
  if (out.isEmpty) {
    out.addAll([if (req.isNotEmpty) req, ...official.where((q) => q != req)]);
  } else {
    for (final q in official) {
      if (!out.contains(q)) out.add(q);
    }
  }
  return out;
}

List<int> secureRandomBytes(int size, {Random? random}) {
  RangeError.checkValueInInterval(size, 0, 65536, 'size');
  final source = random ?? Random.secure();
  return List<int>.generate(size, (_) => source.nextInt(256), growable: false);
}

Map<String, dynamic> buildLxMobileMusicInfo(MusicItem music, String platform) {
  final meta = music.meta ?? const <String, dynamic>{};
  final songmid = music.songmid?.isNotEmpty == true
      ? music.songmid!
      : (meta['songmid'] ?? meta['mid'] ?? music.id).toString();
  final interval = music.duration.inSeconds > 0
      ? '${(music.duration.inSeconds ~/ 60).toString().padLeft(2, '0')}:${(music.duration.inSeconds % 60).toString().padLeft(2, '0')}'
      : (meta['interval']?.toString() ?? '');
  final album = meta['album'];
  final albumMap = album is Map ? album : const <dynamic, dynamic>{};
  final qualities = meta['qualitys'] ?? meta['types'] ?? const <dynamic>[];
  final privateQualities = meta['_qualitys'] ?? meta['_types'] ?? const {};
  return <String, dynamic>{
    'name': music.name,
    'singer': music.singer,
    'source': platform,
    'songmid': songmid,
    'interval': interval,
    'albumName': music.album.isNotEmpty
        ? music.album
        : (meta['albumName'] ?? albumMap['name'] ?? album).toString(),
    'albumId': (meta['albumId'] ?? albumMap['id'] ?? albumMap['mid'] ?? '')
        .toString(),
    'img': music.artwork ?? meta['picUrl']?.toString() ?? '',
    'typeUrl': <String, dynamic>{},
    'types': qualities,
    '_types': privateQualities,
  };
}

Map<String, dynamic> buildSongListDetailParams(
  String id,
  String source,
  int page,
) => {
  'action': 'songListDetail',
  'source': source,
  'info': {'id': id, 'page': page},
};

/// 与原生引擎同名的类型占位：构造参数保留是为了让
/// CustomSourceService / SecureSourceEngine 的调用点零改动。
class CustomSourceEngine {
  CustomSourceEngine({
    SourceRequestPolicy? requestPolicy,
    SourceTransport? requestTransport,
  });

  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final Dio _client = _createClient();

  /// 服务端口令走 HttpOnly cookie，浏览器适配器默认不带 cookie。
  static Dio _createClient() {
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
      ),
    );
    client.httpClientAdapter = BrowserHttpClientAdapter()
      ..withCredentials = true;
    return client;
  }

  LxSourceCapabilities _capabilities = LxSourceCapabilities.fromInitData(null);
  CustomSource? _currentSource;
  bool _disposed = false;

  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  LxSourceCapabilities get capabilities => _capabilities;

  String? effectiveMusicQuality(String platform, String requested) =>
      _capabilities.effectiveQuality(platform, 'musicUrl', requested);

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(path, data: body);
    final data = response.data;
    if (data == null) throw StateError('empty response from $path');
    return data;
  }

  /// 把脚本体推给同容器的 Node 服务编译并注册，再同步它声明的能力表。
  ///
  /// 每次都带脚本体：服务端按 id 去重，脚本没变等价于一次查询；变了就重新
  /// 编译，所以改完脚本重新导入立即生效，不用重启容器。浏览器里没有 QuickJS，
  /// 这是让用户自己导入的音源在 Web 上真正能被执行的唯一通道 —— 只存在
  /// localStorage 里的脚本服务端读不到，取链时必然失败。
  Future<bool> loadSource(CustomSource source) async {
    if (_disposed) return false;
    if (source.script.trim().isEmpty) return false;
    if (_currentSource?.id == source.id && !_capabilities.isEmpty) return true;
    try {
      final data = await _post('/api/sources', <String, dynamic>{
        'id': source.id,
        'name': source.name,
        'script': source.script,
      });
      if (data['ok'] == false) {
        AppLog.instance.record(
          'custom_source.engine',
          'server rejected script "${source.name}": ${data['error']}',
          level: AppLogLevel.error,
        );
        return false;
      }
      _capabilities = LxSourceCapabilities.fromInitData(data);
      _currentSource = source;
      return true;
    } on DioException catch (error) {
      final payload = error.response?.data;
      final reason = payload is Map ? payload['error'] : null;
      // 400 是脚本本身有问题（语法错误 / 没有 lx.send(inited)），值得记下来；
      // 连不上服务只影响本次，界面会再试。
      AppLog.instance.record(
        'custom_source.engine',
        'failed to register "${source.name}": ${reason ?? error.message}',
        level: AppLogLevel.error,
      );
      return false;
    }
  }

  String _resolvePlatform(MusicItem music) {
    const platforms = {'kw', 'tx', 'wy', 'kg', 'mg', 'local'};
    final p = music.platform.toLowerCase();
    if (platforms.contains(p)) return p;
    final fromMeta = music.meta?['source']?.toString().toLowerCase();
    if (fromMeta != null && platforms.contains(fromMeta)) return fromMeta;
    final s = music.source.toLowerCase();
    if (platforms.contains(s)) return s;
    return '';
  }

  Map<String, dynamic> _musicInfo(MusicItem music) {
    final meta = Map<String, dynamic>.from(music.meta ?? const {});
    final raw = <String, dynamic>{
      'songmid': music.songmid ?? music.id,
      'id': music.id,
      'hash': music.hash ?? music.songmid ?? music.id,
      'name': music.name,
      'singer': music.singer,
      'album': music.album,
      'interval': music.duration.inSeconds,
      'img': music.artwork ?? '',
      'meta': meta,
    };
    // 不同脚本习惯从顶层或 meta 里读 hash，两边都放一份。
    for (final entry in meta.entries) {
      raw.putIfAbsent(entry.key, () => entry.value);
    }
    return raw;
  }

  String _absolute(String url) {
    if (url.isEmpty) return url;
    return Uri.base.resolve(url).toString();
  }

  Future<List<MusicItem>> search(
    String keyword, {
    String? source,
    int page = 1,
    int limit = 20,
    String type = 'music',
  }) async {
    final platform = source ?? 'kw';
    try {
      final data = await _post('/api/search', <String, dynamic>{
        'source': platform,
        'keyword': keyword,
        'page': page,
      });
      final list = data['list'];
      if (list is! List) return <MusicItem>[];
      return list
          .whereType<Map>()
          .map((item) => _parseMusicItem(Map<String, dynamic>.from(item)))
          .take(limit)
          .toList();
    } catch (_) {
      return <MusicItem>[];
    }
  }

  MusicItem _parseMusicItem(Map<String, dynamic> item) {
    final info = item['musicInfo'] is Map
        ? Map<String, dynamic>.from(item['musicInfo'] as Map)
        : <String, dynamic>{};
    final meta = info['meta'] is Map
        ? Map<String, dynamic>.from(info['meta'] as Map)
        : <String, dynamic>{};
    final id = (item['id'] ?? info['songmid'] ?? '').toString();
    return MusicItem(
      id: id,
      name: (item['name'] ?? '').toString(),
      singer: (item['singer'] ?? '').toString(),
      album: (item['album'] ?? '').toString(),
      duration: Duration(seconds: (item['interval'] as num?)?.toInt() ?? 0),
      source: _currentSource?.id ?? 'web',
      platform: (item['source'] ?? 'kw').toString(),
      songmid: id,
      hash: (info['hash'] ?? id).toString(),
      meta: meta,
    );
  }

  Future<List<MusicItem>> getSongListDetail(
    String id, {
    String source = 'kw',
    int page = 1,
  }) async {
    try {
      final data = await _post('/api/songlist', <String, dynamic>{
        'source': source,
        'id': id,
        'page': page,
      });
      final list = data['list'];
      if (list is! List) return <MusicItem>[];
      return list
          .whereType<Map>()
          .map((item) => _parseMusicItem(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <MusicItem>[];
    }
  }

  Future<String?> getMusicUrl(
    MusicItem music, {
    String quality = '320k',
  }) async =>
      (await getMusicUrlDetailed(music, quality: quality))?.url;

  Future<({String url, String? type})?> getMusicUrlDetailed(
    MusicItem music, {
    String quality = '320k',
  }) async {
    final platform = _resolvePlatform(music);
    if (platform.isEmpty) return null;
    try {
      final data = await _post('/api/url', <String, dynamic>{
        'source': platform,
        'quality': quality.isEmpty ? '320k' : quality,
        'musicInfo': _musicInfo(music),
      });
      final url = data['url'];
      if (url is! String || url.isEmpty) return null;
      return (url: _absolute(url), type: data['type']?.toString());
    } catch (_) {
      return null;
    }
  }

  Future<String?> getLyric(MusicItem music) async {
    final platform = _resolvePlatform(music);
    if (platform.isEmpty) return null;
    try {
      final data = await _post('/api/lyric', <String, dynamic>{
        'source': platform,
        'musicInfo': _musicInfo(music),
      });
      final lyric = data['lyric'];
      return lyric is String && lyric.isNotEmpty ? lyric : null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _eventController.close();
    _client.close(force: true);
  }
}
