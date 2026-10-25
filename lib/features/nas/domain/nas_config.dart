import 'nas_kind.dart';
import 'nas_url.dart';

enum NasAuthMethod {
  basic,
  bearer;

  String get id => name;

  static NasAuthMethod parse(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'bearer' => NasAuthMethod.bearer,
      _ => NasAuthMethod.basic,
    };
  }
}

class NasConfig {
  const NasConfig({
    required this.kind,
    required this.baseUrl,
    required this.username,
    this.userId = '',
    this.deviceId = '',
    this.rootPath = '/',
    this.authMethod = NasAuthMethod.basic,
    this.enabled = true,
  });

  final NasKind kind;
  final String baseUrl;
  final String username;
  final String userId;
  final String deviceId;

  /// WebDAV root relative to [baseUrl]. It is non-sensitive configuration.
  final String rootPath;

  /// Only used by WebDAV. Credentials are never serialized here.
  final NasAuthMethod authMethod;
  final bool enabled;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  String get hostLabel => nasHostLabel(baseUrl);

  NasConfig copyWith({
    String? baseUrl,
    String? username,
    String? userId,
    String? deviceId,
    String? rootPath,
    NasAuthMethod? authMethod,
    bool? enabled,
  }) {
    return NasConfig(
      kind: kind,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      rootPath: rootPath ?? this.rootPath,
      authMethod: authMethod ?? this.authMethod,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.id,
    'baseUrl': baseUrl,
    'username': username,
    'userId': userId,
    'deviceId': deviceId,
    'rootPath': rootPath,
    'authMethod': authMethod.id,
    'enabled': enabled,
  };

  factory NasConfig.fromJson(NasKind kind, Map<String, dynamic> json) {
    return NasConfig(
      kind: kind,
      baseUrl: (json['baseUrl'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      deviceId: (json['deviceId'] ?? '').toString(),
      rootPath: (json['rootPath'] ?? '/').toString(),
      authMethod: NasAuthMethod.parse(json['authMethod']),
      enabled: json['enabled'] != false,
    );
  }

  static NasConfig empty(NasKind kind) =>
      NasConfig(kind: kind, baseUrl: '', username: '');
}

class NasSecrets {
  const NasSecrets({this.password, this.token});

  final String? password;
  final String? token;

  bool get hasToken => token != null && token!.isNotEmpty;
  bool get hasPassword => password != null && password!.isNotEmpty;
}

class NasSession {
  const NasSession({required this.config, required this.secrets});

  final NasConfig config;
  final NasSecrets secrets;

  String get token => secrets.token ?? '';
}

class NasPlayUrlResult {
  const NasPlayUrlResult({
    required this.url,
    this.headers = const {},
    this.trustedNetwork = false,
  });

  final String url;
  final Map<String, String> headers;

  /// Only trusted NAS clients may opt into private/LAN media transport.
  final bool trustedNetwork;
}

class NasPingResult {
  const NasPingResult({
    required this.ok,
    this.serverType,
    this.serverVersion,
    this.userId,
    this.token,
    this.error,
  });

  final bool ok;
  final String? serverType;
  final String? serverVersion;
  final String? userId;
  final String? token;
  final String? error;
}

class NasPlaylistInfo {
  const NasPlaylistInfo({
    required this.id,
    required this.name,
    this.songCount = 0,
    this.coverArt,
  });

  final String id;
  final String name;
  final int songCount;
  final String? coverArt;
}
