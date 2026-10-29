import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/cache_maintenance_service.dart';

import 'settings_notifiers.dart';

export 'settings_notifiers.dart';

// 音质选择
enum AudioQualityOption {
  low, // 128kbps
  high, // 320kbps
  lossless, // FLAC
  lossless24, // FLAC 24bit（臻品母带）
  hires, // Hi-Res
}

String audioQualityToken(AudioQualityOption quality) => switch (quality) {
  AudioQualityOption.low => '128k',
  AudioQualityOption.high => '320k',
  AudioQualityOption.lossless => 'flac',
  AudioQualityOption.lossless24 => 'flac24bit',
  AudioQualityOption.hires => 'hires',
};

/// 持久化设置 Provider
/// 使用 StorageService（SharedPreferences）存储，重启后保留

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// 主题强调色。照 origo-x：全应用只有一个种子色，浅/深色板都由它生成。
final accentColorProvider = NotifierProvider<AccentColorNotifier, Color>(
  AccentColorNotifier.new,
);

final audioQualityProvider =
    NotifierProvider<AudioQualityNotifier, AudioQualityOption>(
      AudioQualityNotifier.new,
    );

final downloadQualityProvider =
    NotifierProvider<DownloadQualityNotifier, AudioQualityOption>(
      DownloadQualityNotifier.new,
    );

final wifiOnlyDownloadProvider =
    NotifierProvider<WifiOnlyDownloadNotifier, bool>(
      WifiOnlyDownloadNotifier.new,
    );

final autoResumePlaybackProvider =
    NotifierProvider<AutoResumePlaybackNotifier, bool>(
      AutoResumePlaybackNotifier.new,
    );

/// Android overlay player. Off until the user enables it.
final androidFloatingPlayerProvider =
    NotifierProvider<AndroidFloatingPlayerNotifier, bool>(
      AndroidFloatingPlayerNotifier.new,
    );

/// Force the landscape shell and player layout. Phones also lock orientation.
final forceLandscapeProvider = NotifierProvider<ForceLandscapeNotifier, bool>(
  ForceLandscapeNotifier.new,
);

/// Skip frosted glass, transparency, and most motion. Defaults on at 4GB.
final simplifyEffectsProvider = NotifierProvider<SimplifyEffectsNotifier, bool>(
  SimplifyEffectsNotifier.new,
);

/// UI language. `system` follows the device locale.
final appLanguageProvider = NotifierProvider<AppLanguageNotifier, AppLanguage>(
  AppLanguageNotifier.new,
);

/// In-app playback loudness, 0 to 1. Independent of the system volume.
final playbackVolumeProvider = NotifierProvider<PlaybackVolumeNotifier, double>(
  PlaybackVolumeNotifier.new,
);

/// 默认搜索平台：tx / kw / wy / local / favorites / subsonic / NAS
final defaultSearchPlatformProvider =
    NotifierProvider<DefaultSearchPlatformNotifier, String>(
      DefaultSearchPlatformNotifier.new,
    );

/// 全屏播放页背景的模糊档位（0~100，默认 60）与遮罩不透明度（0~1，默认 0.8）。
///
/// 存的是用户档位而不是生效值：性能模式仍会在其上缩放，见
/// `GlassEffectConfig.playerBackdropBlurFor`。
final playerBackdropBlurProvider =
    NotifierProvider<PlayerBackdropBlurNotifier, double>(
      PlayerBackdropBlurNotifier.new,
    );

final playerBackdropScrimProvider =
    NotifierProvider<PlayerBackdropScrimNotifier, double>(
      PlayerBackdropScrimNotifier.new,
    );

final cacheMaintenanceProvider = Provider<CacheMaintenanceService>((ref) {
  return CacheMaintenanceService();
});
