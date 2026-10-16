import 'package:flutter/material.dart';

import 'nas_kind.dart';

/// NAS 音乐服务器的对外类型。设置页和歌单库共用这一套，
/// 主界面只保留一个入口 / 一张卡片。
enum SelfHostedKind {
  subsonic,
  emby,
  jellyfin,
  plex,
  audiostation;

  NasKind? get nasKind => switch (this) {
        subsonic => null,
        emby => NasKind.emby,
        jellyfin => NasKind.jellyfin,
        plex => NasKind.plex,
        audiostation => NasKind.audiostation,
      };

  static SelfHostedKind fromNas(NasKind kind) => switch (kind) {
        NasKind.emby => emby,
        NasKind.jellyfin => jellyfin,
        NasKind.plex => plex,
        NasKind.audiostation => audiostation,
      };

  static SelfHostedKind? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final kind in SelfHostedKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }

  String get chipLabel => switch (this) {
        subsonic => 'Subsonic',
        emby => 'Emby',
        jellyfin => 'Jellyfin',
        plex => 'Plex',
        audiostation => '群晖',
      };

  String get title => switch (this) {
        subsonic => 'Navidrome / Subsonic',
        emby => NasKind.emby.title,
        jellyfin => NasKind.jellyfin.title,
        plex => NasKind.plex.title,
        audiostation => NasKind.audiostation.title,
      };

  String get intro => switch (this) {
        subsonic =>
          '连接 Navidrome / Subsonic / Airsonic / Gonic 等兼容服务器。账号密码只保存在本机钥匙串，不会上传云端。',
        emby => NasKind.emby.intro,
        jellyfin => NasKind.jellyfin.intro,
        plex => NasKind.plex.intro,
        audiostation => NasKind.audiostation.intro,
      };

  String get urlHint => switch (this) {
        subsonic => 'https://music.example.com 或 192.168.1.8:4533',
        emby => NasKind.emby.urlHint,
        jellyfin => NasKind.jellyfin.urlHint,
        plex => NasKind.plex.urlHint,
        audiostation => NasKind.audiostation.urlHint,
      };

  IconData get icon => switch (this) {
        subsonic => Icons.cloud_queue_rounded,
        emby => NasKind.emby.icon,
        jellyfin => NasKind.jellyfin.icon,
        plex => NasKind.plex.icon,
        audiostation => NasKind.audiostation.icon,
      };
}
