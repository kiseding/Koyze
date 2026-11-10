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

final desktopLyricEnabledProvider =
    NotifierProvider<DesktopLyricEnabledNotifier, bool>(
      DesktopLyricEnabledNotifier.new,
    );

final desktopLyricLockedProvider =
    NotifierProvider<DesktopLyricLockedNotifier, bool>(
      DesktopLyricLockedNotifier.new,
    );

final desktopLyricFontSizeProvider =
    NotifierProvider<DesktopLyricFontSizeNotifier, int>(
      DesktopLyricFontSizeNotifier.new,
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
final pitchSemitonesProvider = NotifierProvider<PitchSemitonesNotifier, double>(
  PitchSemitonesNotifier.new,
);

/// 跳过静音（Android）。
final skipSilenceEnabledProvider = NotifierProvider<SkipSilenceNotifier, bool>(
  SkipSilenceNotifier.new,
);

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

/// 界面材质的不透明度倍率（0.3~1，默认 1）。
///
/// 给除播放器以外的所有玻璃面统一缩放染色浓度——它们已经不做背景模糊，
/// 只剩透明度这一档可调。
final glassOpacityProvider = NotifierProvider<GlassOpacityNotifier, double>(
  GlassOpacityNotifier.new,
);

final cacheMaintenanceProvider = Provider<CacheMaintenanceService>((ref) {
  return CacheMaintenanceService();
});

// ---- 歌词显示 ----

/// 歌词整体时间偏移（毫秒）。正值让歌词更晚出现。
final lyricOffsetProvider = NotifierProvider<LyricOffsetNotifier, int>(
  LyricOffsetNotifier.new,
);

/// 歌词字号倍率。
final lyricScaleProvider = NotifierProvider<LyricScaleNotifier, double>(
  LyricScaleNotifier.new,
);

/// 当前行在视口中的纵向位置。
final lyricAlignProvider = NotifierProvider<LyricAlignNotifier, double>(
  LyricAlignNotifier.new,
);

/// 是否显示翻译行。
final lyricTranslationProvider =
    NotifierProvider<LyricTranslationNotifier, bool>(
      LyricTranslationNotifier.new,
    );

/// 是否显示音译（罗马音）行。
final lyricRomanProvider = NotifierProvider<LyricRomanNotifier, bool>(
  LyricRomanNotifier.new,
);

/// 主题色是否跟随当前封面（每首歌一套配色）。
final coverThemedAccentProvider =
    NotifierProvider<CoverThemedAccentNotifier, bool>(
      CoverThemedAccentNotifier.new,
    );

/// 歌词上下两侧的模糊程度（0~1）。
final lyricBlurProvider = NotifierProvider<LyricBlurNotifier, double>(
  LyricBlurNotifier.new,
);

/// 歌词入场动画。索引对应 `SingleLineAnimation.values`。
final lyricEntranceProvider =
    NotifierProvider<SingleLineAnimationNotifier, int>(
      SingleLineAnimationNotifier.new,
    );

/// 播放页背景缓慢漂移。
final flowingBackdropProvider = NotifierProvider<FlowingBackdropNotifier, bool>(
  FlowingBackdropNotifier.new,
);
