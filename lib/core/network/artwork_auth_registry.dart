/// 需要鉴权的封面图地址。
///
/// Emby/Plex 这类把凭证放在 URL 里的协议不需要登记；WebDAV 用
/// `Authorization` 头，而封面是走 `ImageProvider` 单独拉取的，拿不到
/// 播放链路上的 header。这里按 origin 记住当前连接使用的头，加载封面时
/// 再取出来。
library;

final Map<String, Map<String, String>> _registry = {};

String? _originOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return '$scheme://${uri.host.toLowerCase()}:${uri.port}';
}

void registerArtworkAuth(String baseUrl, Map<String, String> headers) {
  final origin = _originOf(baseUrl);
  if (origin == null) return;
  if (headers.isEmpty) {
    _registry.remove(origin);
    return;
  }
  _registry[origin] = Map<String, String>.unmodifiable(headers);
}

void clearArtworkAuth(String baseUrl) {
  final origin = _originOf(baseUrl);
  if (origin == null) return;
  _registry.remove(origin);
}

Map<String, String>? artworkAuthFor(String url) {
  final origin = _originOf(url);
  if (origin == null) return null;
  final headers = _registry[origin];
  return headers == null || headers.isEmpty ? null : headers;
}

/// 仅用于测试：清空全局登记表。
void resetArtworkAuthForTest() => _registry.clear();
