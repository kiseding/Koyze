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

/// 锁屏 / 通知栏歌词开关。
final lockScreenLyricEnabledProvider =
    NotifierProvider<LockScreenLyricNotifier, bool>(
      LockScreenLyricNotifier.new,
    );

/// 响度均衡（ReplayGain）开关。
final replayGainEnabledProvider = NotifierProvider<ReplayGainNotifier, bool>(
  ReplayGainNotifier.new,
);

/// 播放倍速（0.5~2.0 的离散档位）。
final playbackSpeedProvider = NotifierProvider<PlaybackSpeedNotifier, double>(
  PlaybackSpeedNotifier.new,
);

/// 播放音调（±12 半音，0.5 步长）。
final pitchSemitonesProvider =
    NotifierProvider<PitchSemitonesNotifier, double>(
      PitchSemitonesNotifier.new,
    );

/// 跳过静音（Android）。
final skipSilenceEnabledProvider =
    NotifierProvider<SkipSilenceNotifier, bool>(SkipSilenceNotifier.new);

/// 播放/暂停淡入淡出。
final playbackFadeEnabledProvider =
    NotifierProvider<PlaybackFadeNotifier, bool>(PlaybackFadeNotifier.new);

/// 常听预缓存开关。
final precacheEnabledProvider = NotifierProvider<PrecacheEnabledNotifier, bool>(
  PrecacheEnabledNotifier.new,
);

/// 预缓存的曲目数量。
final precacheCountProvider = NotifierProvider<PrecacheCountNotifier, int>(
  PrecacheCountNotifier.new,
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
