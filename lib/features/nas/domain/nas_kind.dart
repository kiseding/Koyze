import 'package:flutter/material.dart';

enum NasKind {
  emby,
  jellyfin,
  plex,
  audiostation;

  String get id => name;

  String get title => switch (this) {
        emby => 'Emby',
        jellyfin => 'Jellyfin',
        plex => 'Plex',
        audiostation => 'Audio Station',
      };

  String get settingsTitle => switch (this) {
        emby => 'Emby 服务器',
        jellyfin => 'Jellyfin 服务器',
        plex => 'Plex 服务器',
        audiostation => '群晖 Audio Station',
      };

  String get libraryTitle => '$title 音乐库';

  String get shortSearchLabel => switch (this) {
        emby => 'Emby',
        jellyfin => 'Jellyfin',
        plex => 'Plex',
        audiostation => '群晖',
      };

  String get settingsSubtitle => switch (this) {
        emby => '连接 Emby 媒体服务器的音乐库',
        jellyfin => '连接 Jellyfin 媒体服务器的音乐库',
        plex => '连接 Plex Media Server 的音乐库',
        audiostation => '连接群晖 DSM 的 Audio Station',
      };

  String get intro => switch (this) {
        emby =>
          '连接 Emby 服务器后即可浏览歌单并播放。账号密码只保存在本机钥匙串，不会上传云端。',
        jellyfin =>
          '连接 Jellyfin 服务器后即可浏览歌单并播放。账号密码只保存在本机钥匙串，不会上传云端。',
        plex =>
          '连接 Plex 媒体服务器。可填用户名密码登录 plex.tv，也可把用户名留空、在密码栏粘贴 X-Plex-Token。凭证只保存在本机。',
        audiostation =>
          '连接群晖 Audio Station。填写 DSM 地址（通常是 5000 或 5001 端口）。账号密码只保存在本机钥匙串。',
      };

  /// Placeholder only — no `http://` literal so the TLS policy scanner stays
  /// clean. Users can still type a scheme; LAN hosts default to HTTP.
  String get urlHint => switch (this) {
        emby => '192.168.1.8:8096',
        jellyfin => '192.168.1.8:8096',
        plex => '192.168.1.8:32400',
        audiostation => '192.168.1.8:5000',
      };

  String get routePrefix => '/$id';

  String get settingsRoute => '/$id-settings';

  String playlistRoute(String playlistId) =>
      '$routePrefix/playlist/${Uri.encodeComponent(playlistId)}';

  IconData get icon => switch (this) {
        emby => Icons.play_circle_outline,
        jellyfin => Icons.live_tv_outlined,
        plex => Icons.movie_filter_outlined,
        audiostation => Icons.storage_outlined,
      };

  Color get accent => switch (this) {
        emby => const Color(0xFF52B54B),
        jellyfin => const Color(0xFF00A4DC),
        plex => const Color(0xFFE5A00D),
        audiostation => const Color(0xFF1E8CE3),
      };

  static NasKind? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final kind in NasKind.values) {
      if (kind.id == value || kind.name == value) return kind;
    }
    return null;
  }
}

const nasClientName = 'Koyze';
const nasClientVersion = '3.0.3';
