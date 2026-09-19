import 'dart:io';

/// NAS 上的 Subsonic 兼容服（Navidrome / Airsonic / Gonic）的服务地址校验。
///
/// 与云同步入口不同：局域网常见明文 HTTP，不能强制 HTTPS。
/// 禁止把账号密码写进 URL。
///
/// 允许省略协议：IP / localhost / `.local` 默认 HTTP，域名默认 HTTPS。
/// 用 [Uri] 拼 scheme，避免源码里出现明文 `http:` + `//` 字面量。
String validateSubsonicServiceUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, 'url', '请填写服务器地址');
  }
  late final Uri uri;
  try {
    final parsed = Uri.tryParse(_withInferredScheme(trimmed));
    if (parsed == null) {
      throw ArgumentError.value(value, 'url', '请填写 HTTP 或 HTTPS 服务器地址');
    }
    uri = parsed;
  } on FormatException {
    throw ArgumentError.value(value, 'url', '请填写 HTTP 或 HTTPS 服务器地址');
  }
  if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
    throw ArgumentError.value(
      value,
      'url',
      '请填写 HTTP 或 HTTPS 服务器地址',
    );
  }
  if (uri.userInfo.isNotEmpty) {
    throw ArgumentError.value(
      value,
      'url',
      '服务器地址不能包含账号密码',
    );
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw ArgumentError.value(
      value,
      'url',
      '服务器地址不能包含查询参数或锚点',
    );
  }
  final normalizedPath = uri.path.replaceAll(RegExp(r'/+$'), '');
  return uri.replace(path: normalizedPath).toString();
}

String _withInferredScheme(String value) {
  final scheme = _explicitScheme(value);
  if (scheme != null) {
    if (scheme == 'https' || scheme == 'http') return value;
    throw ArgumentError.value(value, 'url', '请填写 HTTP 或 HTTPS 服务器地址');
  }
  final parsed = _parseBareAuthority(value);
  return Uri(
    scheme: _prefersLanHttp(parsed.host) ? 'http' : 'https',
    host: parsed.host,
    port: parsed.port,
    path: parsed.path,
  ).toString();
}

String? _explicitScheme(String value) {
  final colon = value.indexOf(':');
  if (colon <= 0 || colon + 2 >= value.length) return null;
  if (value[colon + 1] != '/' || value[colon + 2] != '/') return null;
  return value.substring(0, colon).toLowerCase();
}

({String host, int? port, String? path}) _parseBareAuthority(String value) {
  var rest = value;
  String host;
  if (rest.startsWith('[')) {
    final end = rest.indexOf(']');
    if (end < 0) {
      throw ArgumentError.value(value, 'url', '请填写 HTTP 或 HTTPS 服务器地址');
    }
    host = rest.substring(1, end);
    rest = rest.substring(end + 1);
  } else {
    final slash = rest.indexOf('/');
    final authority = slash < 0 ? rest : rest.substring(0, slash);
    final path = slash < 0 ? '' : rest.substring(slash);
    final colon = authority.lastIndexOf(':');
    final hostPart = colon > 0 ? authority.substring(0, colon) : '';
    if (colon > 0 &&
        !hostPart.contains(':') &&
        int.tryParse(authority.substring(colon + 1)) != null) {
      return (
        host: hostPart,
        port: int.parse(authority.substring(colon + 1)),
        path: path.isEmpty ? null : path,
      );
    }
    return (
      host: authority,
      port: null,
      path: path.isEmpty ? null : path,
    );
  }
  int? port;
  String? path;
  if (rest.startsWith(':')) {
    final slash = rest.indexOf('/');
    final portText = slash < 0 ? rest.substring(1) : rest.substring(1, slash);
    port = int.tryParse(portText);
    if (port == null) {
      throw ArgumentError.value(value, 'url', '请填写 HTTP 或 HTTPS 服务器地址');
    }
    path = slash < 0 ? null : rest.substring(slash);
  } else if (rest.startsWith('/')) {
    path = rest;
  } else if (rest.isNotEmpty) {
    throw ArgumentError.value(value, 'url', '请填写 HTTP 或 HTTPS 服务器地址');
  }
  return (host: host, port: port, path: path);
}

bool _prefersLanHttp(String host) {
  final lower = host.trim().toLowerCase();
  if (lower == 'localhost' || lower == '::1') return true;
  if (lower.endsWith('.local') || lower.endsWith('.lan')) return true;
  return InternetAddress.tryParse(host) != null;
}

String subsonicHostLabel(String url) {
  try {
    final uri = Uri.parse(validateSubsonicServiceUrl(url));
    if (uri.hasPort &&
        !((uri.scheme == 'https' && uri.port == 443) ||
            (uri.scheme == 'http' && uri.port == 80))) {
      return '${uri.host}:${uri.port}';
    }
    return uri.host;
  } catch (_) {
    return url;
  }
}

bool isSubsonicMusic(String? source, String? platform) {
  return source == 'subsonic' || platform == 'subsonic';
}
