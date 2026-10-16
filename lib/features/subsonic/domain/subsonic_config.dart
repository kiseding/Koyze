import 'subsonic_url.dart';

class SubsonicConfig {
  const SubsonicConfig({
    required this.baseUrl,
    required this.username,
    this.legacyAuth = false,
    this.enabled = true,
  });

  final String baseUrl;
  final String username;
  final bool legacyAuth;
  final bool enabled;

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  String get hostLabel => subsonicHostLabel(baseUrl);

  SubsonicConfig copyWith({
    String? baseUrl,
    String? username,
    bool? legacyAuth,
    bool? enabled,
  }) {
    return SubsonicConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      legacyAuth: legacyAuth ?? this.legacyAuth,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'username': username,
        'legacyAuth': legacyAuth,
        'enabled': enabled,
      };

  factory SubsonicConfig.fromJson(Map<String, dynamic> json) {
    return SubsonicConfig(
      baseUrl: (json['baseUrl'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      legacyAuth: json['legacyAuth'] == true,
      enabled: json['enabled'] != false,
    );
  }

  static const empty = SubsonicConfig(baseUrl: '', username: '');
}

class SubsonicPingResult {
  const SubsonicPingResult({
    required this.ok,
    this.serverType,
    this.serverVersion,
    this.openSubsonic = false,
    this.error,
  });

  final bool ok;
  final String? serverType;
  final String? serverVersion;
  final bool openSubsonic;
  final String? error;
}

class SubsonicPlaylistInfo {
  const SubsonicPlaylistInfo({
    required this.id,
    required this.name,
    this.songCount = 0,
    this.coverArt,
    this.owner,
    this.comment,
    this.created,
    this.changed,
  });

  final String id;
  final String name;
  final int songCount;
  final String? coverArt;
  final String? owner;
  final String? comment;
  final DateTime? created;
  final DateTime? changed;
}
